"""
Metriche del server per la pagina "Server" dell'amministrazione: carico della
CPU, memoria, spazio su disco e peso delle cartelle di upload.

In Docker CPU e memoria sono quelle della macchina che ospita i container
(psutil le legge da /proc), non del solo backend; il disco è quello su cui è
montata la cartella uploads.
"""

import asyncio
import logging
import os
import shutil
import threading
import time
from collections import deque
from datetime import datetime, timezone

from app.core.config import settings
from app.services import retention

try:
    import psutil
except ImportError:  # immagine non ricostruita dopo l'aggiunta di psutil a requirements.txt
    psutil = None

logger = logging.getLogger(__name__)

SAMPLE_INTERVAL_SECONDS = 5
HISTORY_SAMPLES = 360         # 30 minuti di andamento della CPU
DIR_USAGE_TTL_SECONDS = 30    # le cartelle di upload si rileggono al massimo ogni 30 s
UPLOAD_DIRS = ("videos", "snapshots", "mock_videos")

STARTED_AT = datetime.now(timezone.utc)

_lock = threading.Lock()
_history = deque(maxlen=HISTORY_SAMPLES)   # (epoch in secondi, % CPU)
_per_core: list = []
_dir_cache: dict = {}                      # cartella -> (scadenza, giri di retention, valori)


async def sampler_loop():
    """Task di background avviato in main.py. psutil misura l'uso della CPU
    tra una chiamata e la successiva dello stesso thread: campionando qui a
    intervalli fissi il valore non dipende da quando arrivano le richieste, e
    la pagina trova già pronto l'andamento degli ultimi minuti."""
    global _per_core
    if psutil is None:
        logger.warning("psutil non installato: CPU e memoria non disponibili nella pagina Server")
        return
    psutil.cpu_percent(percpu=True)  # fissa il punto di partenza: la prima lettura non è significativa
    while True:
        await asyncio.sleep(SAMPLE_INTERVAL_SECONDS)
        try:
            per_core = psutil.cpu_percent(percpu=True)
        except Exception as e:
            logger.warning(f"Lettura CPU fallita: {e}")
            continue
        with _lock:
            _per_core = per_core
            _history.append((int(time.time()), round(sum(per_core) / len(per_core), 1)))


def _cpu(samples: list, per_core: list) -> dict | None:
    if psutil is None:
        return None
    try:
        load_avg = [round(v, 2) for v in psutil.getloadavg()]
    except (AttributeError, OSError):
        load_avg = None
    return {
        "percent": samples[-1][1] if samples else None,
        "per_core": per_core,
        "cores": psutil.cpu_count() or len(per_core),
        "load_avg": load_avg,
    }


def _memory() -> dict | None:
    if psutil is None:
        return None
    vm = psutil.virtual_memory()
    return {"total": vm.total, "used": vm.total - vm.available, "available": vm.available, "percent": vm.percent}


def _disk() -> dict:
    total, used, free = shutil.disk_usage(settings.UPLOAD_DIR)
    # Come df: la percentuale è sullo spazio utilizzabile, senza i blocchi riservati a root
    percent = round(used / (used + free) * 100, 1) if used + free else 0.0
    return {"total": total, "used": used, "free": free, "percent": percent}


def _dir_usage(name: str, retention_runs: int) -> dict:
    """File e byte di una cartella di upload (solo il primo livello, come le scrive vision.py)."""
    now = time.monotonic()
    cached = _dir_cache.get(name)
    # Un giro di retention cambia il contenuto: i valori in cache non valgono più
    if cached and cached[0] > now and cached[1] == retention_runs:
        return cached[2]
    files = size = 0
    oldest = None
    try:
        with os.scandir(os.path.join(settings.UPLOAD_DIR, name)) as entries:
            for entry in entries:
                try:
                    if entry.name.startswith(".") or not entry.is_file(follow_symlinks=False):
                        continue
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    continue  # file eliminato durante la lettura
                files += 1
                size += st.st_size
                oldest = st.st_mtime if oldest is None else min(oldest, st.st_mtime)
    except OSError:
        pass
    usage = {
        "files": files,
        "bytes": size,
        "oldest_at": datetime.fromtimestamp(oldest, timezone.utc) if oldest is not None else None,
    }
    _dir_cache[name] = (now + DIR_USAGE_TTL_SECONDS, retention_runs, usage)
    return usage


def snapshot() -> dict:
    """Stato corrente del server, restituito da GET /sla/server."""
    retention_status = retention.status()
    runs = retention_status["totals"]["runs"]
    with _lock:
        samples, per_core = list(_history), _per_core
    return {
        "timestamp": datetime.now(timezone.utc),
        "started_at": STARTED_AT,
        "boot_time": datetime.fromtimestamp(psutil.boot_time(), timezone.utc) if psutil else None,
        "cpu": _cpu(samples, per_core),
        "memory": _memory(),
        "disk": _disk(),
        "uploads": {name: _dir_usage(name, runs) for name in UPLOAD_DIRS},
        "retention": retention_status,
        "history": {"interval_seconds": SAMPLE_INTERVAL_SECONDS, "samples": samples},
    }
