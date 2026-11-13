"""
Endpoint dedicati al nodo di visione (telecamera IA locale).

Autenticazione: header X-MAC-Address (stesso meccanismo dei device ESP32),
tramite get_current_camera (richiede che il device sia già seminato nel DB
con type='camera').

- POST /api/vision/snapshot -> carica una foto e restituisce l'URL pubblico
  da usare come "frame_url" nel payload MQTT dell'evento.
- POST /api/vision/clip -> carica una clip video e la associa all'evento
  "alert" più recente di questa telecamera (creato pochi secondi prima via
  MQTT), così la dashboard può mostrare il bottone "VIDEO" nel timeline.
"""

import datetime as dt
import logging
import os
import shutil
import subprocess

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_camera, get_db
from app.core.config import settings
from app.db.models import Device, Event, EventVideo, TypeEvent

logger = logging.getLogger(__name__)

router = APIRouter()

# Finestra entro cui una clip caricata dopo l'evento viene agganciata
# all'evento più recente della stessa telecamera (l'evento arriva via MQTT,
# la clip arriva ~10s dopo via HTTP: vedi video_clip.py sul nodo camera).
CLIP_MATCH_WINDOW_SECONDS = 60


def _abs_url(rel_url: str) -> str:
    base = settings.BASE_URL.rstrip("/")
    return f"{base}{rel_url}" if rel_url.startswith("/") else rel_url


def transcode_to_h264(input_path: str, output_path: str) -> bool:
    """
    Converte un file video in formato H.264 (AVC1, YUV420p) con atomo moov
    all'inizio (+faststart), garantendo la compatibilità con tutti i browser
    web e i tag <video> HTML5.
    """
    try:
        cmd = [
            "ffmpeg",
            "-y",
            "-i", input_path,
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "23",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-an",
            output_path,
        ]
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            check=False,
        )
        if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return True
        logger.error(
            f"FFmpeg transcode fallito (code {res.returncode}): "
            f"{res.stderr.decode('utf-8', errors='ignore')[-300:]}"
        )
        return False
    except Exception as e:
        logger.error(f"Errore durante transcodifica video con FFmpeg: {e}")
        return False


def generate_thumbnail(video_path: str, thumb_path: str) -> bool:
    """Estrae un fotogramma JPG da usare come thumbnail."""
    try:
        cmd = [
            "ffmpeg",
            "-y",
            "-ss", "00:00:01",
            "-i", video_path,
            "-vframes", "1",
            "-q:v", "2",
            thumb_path,
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
        return res.returncode == 0 and os.path.exists(thumb_path) and os.path.getsize(thumb_path) > 0
    except Exception:
        return False


def get_video_duration(video_path: str) -> float | None:
    """Ricava la durata in secondi del video tramite ffprobe."""
    try:
        cmd = [
            "ffprobe",
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            video_path,
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, check=False)
        if res.returncode == 0:
            val = res.stdout.decode().strip()
            return round(float(val), 2)
    except Exception:
        pass
    return None


@router.get("/me")
def camera_me(current_device: Device = Depends(get_current_camera)):
    """Verifica che la telecamera sia registrata e autorizzata."""
    return {
        "ok": True,
        "mac_address": current_device.mac_address,
        "zone": current_device.zone,
        "type": current_device.type.value if hasattr(current_device.type, 'value') else current_device.type,
        "status": current_device.status or "ok",
    }


@router.post("/snapshot")
async def upload_snapshot(
    file: UploadFile = File(...),
    current_device: Device = Depends(get_current_camera),
):
    """Salva uno snapshot jpg e restituisce l'URL pubblico da mettere in frame_url."""
    snapshots_dir = os.path.join(settings.UPLOAD_DIR, "snapshots")
    os.makedirs(snapshots_dir, exist_ok=True)

    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    ext = os.path.splitext(file.filename)[1] if file.filename else ".jpg"
    if not ext:
        ext = ".jpg"
    mac_slug = current_device.mac_address.replace(":", "")
    file_name = f"{mac_slug}_{timestamp}{ext}"
    file_path = os.path.join(snapshots_dir, file_name)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    rel_url = f"/static/snapshots/{file_name}"
    logger.info(f"Snapshot salvato: {file_path}")
    return {"url": _abs_url(rel_url)}


@router.post("/clip")
async def upload_clip(
    file: UploadFile = File(...),
    device_id: str = Form(None),
    event_type: str = Form(None),
    timestamp: int = Form(None),
    current_device: Device = Depends(get_current_camera),
    db: Session = Depends(get_db),
):
    """Salva una clip mp4, la converte in H.264 web-compatible e la associa all'evento 'alert' più recente."""
    videos_dir = settings.VIDEOS_DIR
    os.makedirs(videos_dir, exist_ok=True)

    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%S")
    ext = os.path.splitext(file.filename)[1] if file.filename else ".mp4"
    if not ext:
        ext = ".mp4"
    mac_slug = current_device.mac_address.replace(":", "")
    base_file_name = f"{mac_slug}_{ts}"
    file_name = f"{base_file_name}.mp4"
    file_path = os.path.join(videos_dir, file_name)

    raw_path = os.path.join(videos_dir, f"{base_file_name}_raw{ext}")
    with open(raw_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Transcodifica in H.264 (AVC1) con +faststart per browser web
    if transcode_to_h264(raw_path, file_path):
        try:
            os.remove(raw_path)
        except OSError:
            pass
        logger.info(f"Clip transcodificata con successo in H.264 web-standard: {file_path}")
    else:
        # Fallback: se FFmpeg non è disponibile o fallisce, mantieni il file originale
        logger.warning(f"Transcodifica non riuscita, uso file sorgente: {file_path}")
        if os.path.exists(file_path):
            os.remove(file_path)
        os.rename(raw_path, file_path)

    # Genera thumbnail e durata
    thumb_name = f"{base_file_name}_thumb.jpg"
    thumb_path = os.path.join(videos_dir, thumb_name)
    thumbnail_url = None
    if generate_thumbnail(file_path, thumb_path):
        thumbnail_url = f"/static/videos/{thumb_name}"

    duration_seconds = get_video_duration(file_path)

    video_url = f"/static/videos/{file_name}"
    logger.info(f"Clip pronta: {file_path}")

    # Cerca l'evento 'alert' più recente di questa telecamera senza già un video
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=CLIP_MATCH_WINDOW_SECONDS)
    event = (
        db.query(Event)
        .outerjoin(EventVideo, Event.id == EventVideo.id_event)
        .filter(
            Event.mac_address == current_device.mac_address,
            Event.type == TypeEvent.alert,
            Event.transmission_time >= cutoff,
            EventVideo.id.is_(None),
        )
        .order_by(Event.transmission_time.desc())
        .first()
    )

    if not event:
        logger.warning(
            f"Nessun evento 'alert' recente trovato per {current_device.mac_address}: "
            f"clip salvata ma non collegata a nessuna pratica."
        )
        return {
            "video_url": _abs_url(video_url),
            "thumbnail_url": _abs_url(thumbnail_url) if thumbnail_url else None,
            "duration_seconds": duration_seconds,
            "event_id": None,
        }

    new_video = EventVideo(
        id_event=event.id,
        video_url=video_url,
        thumbnail_url=thumbnail_url,
        duration_seconds=duration_seconds,
        created_at=dt.datetime.now(dt.timezone.utc),
    )
    db.add(new_video)
    db.commit()

    return {
        "video_url": _abs_url(video_url),
        "thumbnail_url": _abs_url(thumbnail_url) if thumbnail_url else None,
        "duration_seconds": duration_seconds,
        "event_id": event.id,
    }
