"""
Retention delle clip video: per non riempire il disco, le clip salvate da
POST /api/vision/clip vengono eliminate quando hanno più di
VIDEO_RETENTION_MINUTES (default 60, 0 = mai).

Di ogni clip scaduta si tolgono mp4, thumbnail e riga EventVideo, così la
dashboard non propone più un video che non esiste. Per le clip collegate a un
evento decide la data della riga; per i file senza riga (clip arrivata senza
un evento 'alert' a cui agganciarla, sorgenti "_raw" rimasti da una
transcodifica interrotta) decide la data del file.

Resta fuori uploads/mock_videos (clip fissa del modellino).

Retention delle pratiche: le pratiche con dati di telecamere o microfoni
(fotogramma, numero di persone, audio) vengono eliminate PRACTICE_RETENTION_HOURS
dopo la creazione (default 48, 0 = mai), come da informativa privacy. Le altre
(cestini, suolo, segnalazioni dei cittadini) restano PRACTICE_RETENTION_DAYS_NON_SECURITY
giorni (default 30, 0 = mai): sono lavoro da fare, non videosorveglianza. In
entrambi i casi in qualunque stato, insieme agli eventi che le compongono. Gli
eventi che non generano pratiche (varchi, consumi elettrici) non vengono toccati.

Con il termine delle 48 ore si eliminano gli snapshot in uploads/snapshots. Lo
snapshot arriva prima dell'evento ed è legato solo da frame_url, quindi decide
la data del file.

Retention delle segnalazioni dei cittadini: quelle risolte o chiuse da più di
CITIZEN_REPORT_RETENTION_DAYS (default 30, 0 = mai) vengono eliminate con storico e
foto; i cittadini senza segnalazioni e inattivi da CITIZEN_INACTIVE_DAYS (default
365, 0 = mai) vengono eliminati.
"""

import asyncio
import logging
import os
import posixpath
import threading
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from sqlalchemy import and_, or_, select

from app.core.config import settings
from app.db.database import SessionLocal
from app.db.models import (
    Citizen, CitizenReport, Device, Event, EventCamera, EventMicrophone, EventVideo, Practice, TypeDevice, practice_event,
)
from app.services.citizen import delete_photo, detach_reports, notify_reports

logger = logging.getLogger(__name__)

# Minimo tra due giri: con un intervallo configurato a 0 il loop girerebbe a vuoto
MIN_INTERVAL_SECONDS = 30

# Il giro automatico e quello manuale (POST /sla/server/cleanup) non si sovrappongono
_lock = threading.Lock()
# Esito dell'ultimo giro e totali dall'avvio del backend, mostrati nella pagina "Server"
_stats = {"last_run": None, "next_run_at": None, "runs": 0, "deleted_files": 0, "freed_bytes": 0}
_practice_stats = {"last_run": None, "deleted_practices": 0, "deleted_events": 0, "deleted_snapshots": 0}
_citizen_stats = {"last_run": None, "deleted_reports": 0, "deleted_photos": 0, "deleted_citizens": 0}

SNAPSHOTS_DIR = os.path.join(settings.UPLOAD_DIR, "snapshots")


def is_enabled() -> bool:
    return settings.VIDEO_RETENTION_MINUTES > 0


def _interval() -> int:
    return max(MIN_INTERVAL_SECONDS, settings.VIDEO_CLEANUP_INTERVAL_SECONDS)


def _clip_name(url: str | None) -> str | None:
    """Nome del file in VIDEOS_DIR a cui punta un URL salvato in EventVideo
    ("/static/videos/x.mp4", anche assoluto). None se punta altrove."""
    if not url:
        return None
    path = urlparse(url).path
    name = posixpath.basename(path)
    if posixpath.basename(posixpath.dirname(path)) != "videos" or name.startswith("."):
        return None
    return name or None


def _remove(path: str, result: dict) -> None:
    try:
        size = os.path.getsize(path)
        os.remove(path)
    except FileNotFoundError:
        return
    except OSError as e:
        result["errors"] += 1
        logger.warning(f"Retention: impossibile eliminare {path}: {e}")
        return
    result["deleted_files"] += 1
    result["freed_bytes"] += size


def cleanup_old_videos() -> dict:
    """Elimina le clip più vecchie di VIDEO_RETENTION_MINUTES e restituisce l'esito del giro."""
    now = datetime.now(timezone.utc)
    result = {"at": now, "deleted_files": 0, "freed_bytes": 0, "deleted_rows": 0, "errors": 0}
    if not is_enabled():
        return result
    cutoff = now - timedelta(minutes=settings.VIDEO_RETENTION_MINUTES)

    with _lock:
        keep, expired = set(), set()
        with SessionLocal() as db:
            # Clip ancora valide: i loro file non si toccano, qualunque data abbiano su disco
            for video_url, thumbnail_url in (
                db.query(EventVideo.video_url, EventVideo.thumbnail_url)
                .filter(EventVideo.created_at >= cutoff)
                .all()
            ):
                keep.update(n for n in (_clip_name(video_url), _clip_name(thumbnail_url)) if n)

            for video in db.query(EventVideo).filter(EventVideo.created_at < cutoff).all():
                name = _clip_name(video.video_url)
                if not name:
                    continue  # video che non sta in uploads/videos: non è spazio gestito qui
                expired.update(n for n in (name, _clip_name(video.thumbnail_url)) if n)
                db.delete(video)
                result["deleted_rows"] += 1
            # Prima le righe, poi i file: se il processo si ferma a metà restano file
            # senza riga (li toglie il giro successivo), mai righe senza file
            db.commit()

        cutoff_ts = cutoff.timestamp()
        with os.scandir(settings.VIDEOS_DIR) as entries:
            for entry in entries:
                if entry.name.startswith(".") or entry.name in keep:
                    continue
                try:
                    if not entry.is_file(follow_symlinks=False):
                        continue
                    old = entry.name in expired or entry.stat(follow_symlinks=False).st_mtime < cutoff_ts
                except OSError:
                    continue
                if old:
                    _remove(entry.path, result)

        _stats["last_run"] = result
        _stats["runs"] += 1
        _stats["deleted_files"] += result["deleted_files"]
        _stats["freed_bytes"] += result["freed_bytes"]

    if result["deleted_files"] or result["deleted_rows"]:
        logger.info(
            f"Retention video: {result['deleted_files']} file eliminati "
            f"({result['freed_bytes']} byte), {result['deleted_rows']} righe event_video"
        )
    return result


def practices_enabled() -> bool:
    return settings.PRACTICE_RETENTION_HOURS > 0 or settings.PRACTICE_RETENTION_DAYS_NON_SECURITY > 0


def _with_av_data():
    """practice_id delle pratiche con almeno un evento di telecamera o microfono:
    device di quel tipo, oppure dettaglio camera/microfono (anche gli allarmi
    sintetici). Sono quelle con dati personali, coperte dal termine delle 48 ore."""
    return (
        select(practice_event.c.practice_id)
        .join(Event, Event.id == practice_event.c.event_id)
        .outerjoin(Device, Device.mac_address == Event.mac_address)
        .where(or_(
            Device.type.in_([TypeDevice.camera, TypeDevice.microphone]),
            Event.id.in_(select(EventCamera.event_id)),
            Event.id.in_(select(EventMicrophone.event_id)),
        ))
    )


def _cleanup_old_snapshots(cutoff: datetime) -> int:
    """Elimina gli snapshot caricati prima di cutoff e restituisce quanti file ha tolto."""
    removed = {"deleted_files": 0, "freed_bytes": 0, "errors": 0}
    cutoff_ts = cutoff.timestamp()
    try:
        entries = list(os.scandir(SNAPSHOTS_DIR))
    except FileNotFoundError:
        return 0  # nessuno snapshot ancora caricato
    for entry in entries:
        if entry.name.startswith("."):
            continue
        try:
            if not entry.is_file(follow_symlinks=False) or entry.stat(follow_symlinks=False).st_mtime >= cutoff_ts:
                continue
        except OSError:
            continue
        _remove(entry.path, removed)
    return removed["deleted_files"]


def cleanup_old_practices() -> dict:
    """Elimina le pratiche scadute (48 ore con dati di telecamere o microfoni, 30 giorni
    le altre), i loro eventi e gli snapshot."""
    now = datetime.now(timezone.utc)
    result = {"at": now, "deleted_practices": 0, "deleted_events": 0, "deleted_snapshots": 0}
    if not practices_enabled():
        return result
    av = _with_av_data()
    rules = []
    if settings.PRACTICE_RETENTION_HOURS > 0:
        cutoff = now - timedelta(hours=settings.PRACTICE_RETENTION_HOURS)
        rules.append(and_(Practice.created_at < cutoff, Practice.id.in_(av)))
    if settings.PRACTICE_RETENTION_DAYS_NON_SECURITY > 0:
        rules.append(and_(Practice.created_at < now - timedelta(days=settings.PRACTICE_RETENTION_DAYS_NON_SECURITY),
                          Practice.id.notin_(av)))
    is_expired = or_(*rules)

    with _lock, SessionLocal() as db:
        expired = db.query(Practice.id).filter(is_expired)
        # Eventi delle pratiche scadute, tranne quelli agganciati anche a una pratica che resta
        kept = db.query(practice_event.c.event_id).filter(practice_event.c.practice_id.notin_(expired))
        event_ids = [
            eid for (eid,) in db.query(practice_event.c.event_id)
            .filter(practice_event.c.practice_id.in_(expired), practice_event.c.event_id.notin_(kept))
            .distinct()
        ]
        # Le segnalazioni dei cittadini restano: quelle ancora aperte passano a "Chiusa automaticamente"
        closed_reports = detach_reports(db, expired)
        # practice_event, practice_audit e le tabelle di dettaglio degli eventi seguono per ON DELETE CASCADE
        result["deleted_practices"] = (
            db.query(Practice).filter(is_expired).delete(synchronize_session=False)
        )
        for i in range(0, len(event_ids), 1000):
            result["deleted_events"] += (
                db.query(Event).filter(Event.id.in_(event_ids[i:i + 1000])).delete(synchronize_session=False)
            )
        db.commit()
        notify_reports(closed_reports)  # lo stato del parco lo aggiorna park_watch_loop
        if settings.PRACTICE_RETENTION_HOURS > 0:
            result["deleted_snapshots"] = _cleanup_old_snapshots(cutoff)
        _practice_stats["last_run"] = result
        _practice_stats["deleted_practices"] += result["deleted_practices"]
        _practice_stats["deleted_events"] += result["deleted_events"]
        _practice_stats["deleted_snapshots"] += result["deleted_snapshots"]

    if result["deleted_practices"] or result["deleted_snapshots"]:
        logger.info(
            f"Retention segnalazioni: {result['deleted_practices']} pratiche, "
            f"{result['deleted_events']} eventi e {result['deleted_snapshots']} snapshot eliminati"
        )
    return result


def citizen_enabled() -> bool:
    return settings.CITIZEN_REPORT_RETENTION_DAYS > 0 or settings.CITIZEN_INACTIVE_DAYS > 0


def cleanup_old_citizen_reports() -> dict:
    """Elimina le segnalazioni risolte o chiuse da più di CITIZEN_REPORT_RETENTION_DAYS
    (con storico e foto) e i cittadini senza segnalazioni inattivi da CITIZEN_INACTIVE_DAYS."""
    now = datetime.now(timezone.utc)
    result = {"at": now, "deleted_reports": 0, "deleted_photos": 0, "deleted_citizens": 0}
    if not citizen_enabled():
        return result

    with _lock, SessionLocal() as db:
        if settings.CITIZEN_REPORT_RETENTION_DAYS > 0:
            cutoff = now - timedelta(days=settings.CITIZEN_REPORT_RETENTION_DAYS)
            # updated_at = momento dell'ultimo cambio di stato, cioè della chiusura
            rows = (
                db.query(CitizenReport.id, CitizenReport.photo_path)
                .filter(CitizenReport.status.in_(("resolved", "closed")), CitizenReport.updated_at < cutoff)
                .all()
            )
            ids = [r.id for r in rows]
            # citizen_report_history segue per ON DELETE CASCADE, event_citizen.report_id va a NULL
            for i in range(0, len(ids), 1000):
                result["deleted_reports"] += (
                    db.query(CitizenReport).filter(CitizenReport.id.in_(ids[i:i + 1000])).delete(synchronize_session=False)
                )
            db.commit()
            # Prima le righe, poi i file: se il processo si ferma a metà resta al più un file orfano
            for r in rows:
                if r.photo_path:
                    delete_photo(r.photo_path)
                    result["deleted_photos"] += 1

        if settings.CITIZEN_INACTIVE_DAYS > 0:
            cutoff = now - timedelta(days=settings.CITIZEN_INACTIVE_DAYS)
            result["deleted_citizens"] = (
                db.query(Citizen)
                .filter(Citizen.id.notin_(select(CitizenReport.citizen_id)),
                        or_(Citizen.last_seen_at < cutoff,
                            and_(Citizen.last_seen_at.is_(None), Citizen.created_at < cutoff)))
                .delete(synchronize_session=False)
            )
            db.commit()

        _citizen_stats["last_run"] = result
        for k in ("deleted_reports", "deleted_photos", "deleted_citizens"):
            _citizen_stats[k] += result[k]

    if result["deleted_reports"] or result["deleted_citizens"]:
        logger.info(
            f"Retention cittadini: {result['deleted_reports']} segnalazioni ({result['deleted_photos']} foto) "
            f"e {result['deleted_citizens']} installazioni inattive eliminate"
        )
    return result


def status() -> dict:
    """Configurazione ed esito dei giri, per la pagina "Server" dell'amministrazione."""
    return {
        "enabled": is_enabled(),
        "retention_minutes": settings.VIDEO_RETENTION_MINUTES,
        "interval_seconds": _interval(),
        "next_run_at": _stats["next_run_at"],
        "last_run": _stats["last_run"],
        "totals": {k: _stats[k] for k in ("runs", "deleted_files", "freed_bytes")},
        "practices": {
            "enabled": practices_enabled(),
            "retention_hours": settings.PRACTICE_RETENTION_HOURS,
            "retention_days_non_security": settings.PRACTICE_RETENTION_DAYS_NON_SECURITY,
            "last_run": _practice_stats["last_run"],
            "totals": {k: _practice_stats[k] for k in ("deleted_practices", "deleted_events", "deleted_snapshots")},
        },
        "citizen_reports": {
            "enabled": citizen_enabled(),
            "retention_days": settings.CITIZEN_REPORT_RETENTION_DAYS,
            "inactive_days": settings.CITIZEN_INACTIVE_DAYS,
            "last_run": _citizen_stats["last_run"],
            "totals": {k: _citizen_stats[k] for k in ("deleted_reports", "deleted_photos", "deleted_citizens")},
        },
    }


async def retention_loop():
    """Task di background avviato in main.py: un giro subito, poi uno ogni VIDEO_CLEANUP_INTERVAL_SECONDS."""
    if not is_enabled() and not practices_enabled() and not citizen_enabled():
        logger.info("Retention disattivata (tutti i termini a 0)")
        return
    while True:
        # In un thread: cancellare file e righe non deve fermare l'event loop.
        # Prima le pratiche: le clip dei loro eventi restano senza riga e le toglie il giro video
        for job in (cleanup_old_practices, cleanup_old_videos, cleanup_old_citizen_reports):
            try:
                await asyncio.to_thread(job)
            except Exception as e:
                logger.error(f"Retention: {job.__name__} fallito: {e}")
        _stats["next_run_at"] = datetime.now(timezone.utc) + timedelta(seconds=_interval())
        await asyncio.sleep(_interval())
