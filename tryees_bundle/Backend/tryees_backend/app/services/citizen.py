"""Logica delle segnalazioni dei cittadini condivisa dagli endpoint /citizen e
dalle API operatori: foto, etichette, stato che segue la pratica, notifiche live."""
import asyncio, logging, os, secrets, threading
from collections import Counter
from datetime import datetime, timezone
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import or_

from app.core.citizen_ws import citizen_ws_manager
from app.core.config import settings
from app.db.database import SessionLocal
from app.db.models import (
    CitizenCategory, CitizenReport, CitizenReportHistory, Event, EventCitizen, Park, ParkNotice, Practice, PracticeStatus, TypeEvent,
)

logger = logging.getLogger(__name__)

PHOTO_MAX_BYTES  = 5 * 1024 * 1024  # contratto con l'app: max 5 MB
PHOTO_MAX_SIDE   = 1600
PHOTO_MAX_PIXELS = 40_000_000       # oltre è una decompression bomb, non una foto di telefono
PHOTO_DIR        = "citizen"        # sotto UPLOAD_DIR, quindi servita da /static/citizen/

STATUS_LABELS = {
    "received": "Ricevuta",
    "in_progress": "In lavorazione",
    "resolved": "Risolta",
    "closed": "Chiusa",
}
SUMMARY_LEN = 80


class PhotoError(ValueError):
    pass


def process_photo(data: bytes) -> bytes:
    """Valida la foto (JPEG o PNG, decisi dal contenuto e non dall'estensione) e la
    ricodifica in JPEG di al massimo PHOTO_MAX_SIDE px. La ricodifica non copia
    gli EXIF: spariscono anche coordinate GPS e modello del telefono."""
    try:
        with Image.open(BytesIO(data)) as probe:
            fmt, (w, h) = probe.format, probe.size
            probe.verify()
    except Image.DecompressionBombError:
        raise PhotoError("La foto ha una risoluzione troppo alta")
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError):
        raise PhotoError("La foto non è un'immagine valida")
    if fmt not in ("JPEG", "PNG"):
        raise PhotoError("La foto deve essere JPEG o PNG")
    if w * h > PHOTO_MAX_PIXELS:
        raise PhotoError("La foto ha una risoluzione troppo alta")

    try:
        with Image.open(BytesIO(data)) as img:  # verify() rende inutilizzabile l'immagine: si riapre
            img = ImageOps.exif_transpose(img)  # raddrizza prima di perdere l'orientamento EXIF
            if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                rgba = img.convert("RGBA")
                img = Image.new("RGB", rgba.size, (255, 255, 255))
                img.paste(rgba, mask=rgba.getchannel("A"))
            else:
                img = img.convert("RGB")
            img.thumbnail((PHOTO_MAX_SIDE, PHOTO_MAX_SIDE))
            out = BytesIO()
            img.save(out, "JPEG", quality=85, optimize=True)
    except (OSError, ValueError, Image.DecompressionBombError):
        raise PhotoError("La foto non è un'immagine valida")
    return out.getvalue()


def save_photo(jpeg: bytes) -> str:
    """Salva la foto con un nome casuale e restituisce il percorso relativo a UPLOAD_DIR."""
    folder = os.path.join(settings.UPLOAD_DIR, PHOTO_DIR)
    os.makedirs(folder, exist_ok=True)
    name = f"{secrets.token_hex(16)}.jpg"
    with open(os.path.join(folder, name), "wb") as f:
        f.write(jpeg)
    return f"{PHOTO_DIR}/{name}"


def delete_photo(photo_path: str | None) -> None:
    if not photo_path:
        return
    try:
        os.remove(os.path.join(settings.UPLOAD_DIR, photo_path))
    except FileNotFoundError:
        pass


def photo_url(photo_path: str | None) -> str | None:
    return f"/static/{photo_path}" if photo_path else None


def as_utc(value: datetime) -> datetime:
    """Date in UTC senza microsecondi (…T10:20:31Z). SQLite le restituisce senza fuso."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).replace(microsecond=0)


def iso_z(value: datetime) -> str:
    """Data per i messaggi WebSocket, nello stesso formato delle API: …T10:20:31Z."""
    return as_utc(value).isoformat().replace("+00:00", "Z")


def report_code(report) -> str:
    return f"SEG-{report.created_at.year}-{report.id:06d}"


def summary(text: str) -> str:
    text = " ".join(text.split())
    return text if len(text) <= SUMMARY_LEN else text[:SUMMARY_LEN - 1].rstrip() + "…"


# --- Stato della segnalazione, che segue la pratica ---------------------------

# Stato della pratica → stato visto dal cittadino
PRACTICE_TO_REPORT = {"open": "received", "in_progress": "in_progress", "resolved": "resolved", "closed": "closed"}
AUTO_CLOSE_NOTE = "Chiusa automaticamente"


def set_status(report, new_status: str, note: str | None, now: datetime) -> None:
    report.status = new_status
    report.updated_at = now
    report.history.append(CitizenReportHistory(status=new_status, note=note, at=now))


def sync_reports(db, practice, note: str | None = None) -> list:
    """Porta le segnalazioni collegate alla pratica allo stato corrispondente,
    con una riga di storico per ogni cambio. `note` è visibile al cittadino.
    Restituisce le segnalazioni cambiate (per le notifiche al cittadino)."""
    status = practice.status.value if hasattr(practice.status, "value") else str(practice.status)
    target = PRACTICE_TO_REPORT[status]
    now = datetime.now(timezone.utc)
    changed = (
        db.query(CitizenReport)
        .filter(CitizenReport.practice_id == practice.id, CitizenReport.status != target)
        .all()
    )
    for r in changed:
        set_status(r, target, note, now)
    if changed:
        db.commit()
        notify_reports(changed)
    return changed


def notify_reports(reports) -> None:
    """report_updated al solo proprietario di ogni segnalazione (formato slide 21)."""
    for r in reports:
        citizen_ws_manager.send_to_citizen_from_thread(r.citizen_id, {"type": "report_updated", "data": {
            "report_id": r.id, "status": r.status, "status_label": STATUS_LABELS[r.status],
            "at": iso_z(r.updated_at),
        }})


def detach_reports(db, practice_ids) -> list:
    """Da chiamare prima di cancellare pratiche (retention, DELETE admin): le
    segnalazioni ancora aperte passano a 'closed' con una nota, così il cittadino
    non resta con una segnalazione "in lavorazione" per sempre. La FK practice_id
    va poi a NULL da sola (ON DELETE SET NULL). Non fa commit: lo fa il chiamante
    insieme alla cancellazione, e dopo chiama notify_reports con il risultato."""
    now = datetime.now(timezone.utc)
    reports = (
        db.query(CitizenReport)
        .filter(CitizenReport.practice_id.in_(practice_ids),
                CitizenReport.status.notin_(("resolved", "closed")))
        .all()
    )
    for r in reports:
        set_status(r, "closed", AUTO_CLOSE_NOTE, now)
    return reports


def correlate_report(db, report) -> None:
    """Problema → evento 'citizen' → correlazione, come un evento sensore. Un
    errore qui non fa perdere la segnalazione, già salvata: si registra e basta."""
    from app.core.ws_manager import ws_manager
    from app.services.correlation import correlation_engine
    try:
        now = report.created_at or datetime.now(timezone.utc)
        event = Event(mac_address=None, type=TypeEvent.citizen, sampling_time=now, transmission_time=now)
        db.add(event); db.flush()
        db.add(EventCitizen(event_id=event.id, report_id=report.id, lat=report.lat, lon=report.lon,
                            category=report.category, priority=report.priority))
        report.event_id = event.id
        db.commit(); db.refresh(event)

        practice, is_new = correlation_engine.process_event(event, db)
        if practice is None:
            return
        report.practice_id = practice.id
        db.commit()
        sync_reports(db, practice)  # se la pratica era già presa in carico, lo è anche la segnalazione
        ws_manager.broadcast_from_thread(operator_message(practice, event, is_new))
        refresh_park(db, report.park_id)
    except Exception as e:
        db.rollback()
        logger.error(f"Correlazione della segnalazione {report.id} fallita: {e}")


# --- Stato del parco e avvisi -------------------------------------------------

LEVEL_MESSAGES = {
    "ok": "Tutto regolare",
    "warning": "Alcune situazioni in gestione",
    "alert": "Attenzione: leggi gli avvisi del parco",
}
NOTICE_LEVEL_ORDER = {"alert": 0, "warning": 1, "info": 2}
# Pratiche dei soli sensori mostrate ai cittadini. Le altre (sicurezza, telecamere,
# luci) restano fuori: il cittadino non vede mai dati di sicurezza.
SENSOR_PUBLIC_CATEGORY = {"basket": "waste", "soil": "green"}


def active_notices(db, park_id: int, now: datetime | None = None) -> list:
    """Avvisi in corso: iniziati e non ancora finiti. Prima i più gravi, poi i più recenti."""
    now = now or datetime.now(timezone.utc)
    rows = (
        db.query(ParkNotice)
        .filter(ParkNotice.park_id == park_id, ParkNotice.starts_at <= now,
                or_(ParkNotice.ends_at.is_(None), ParkNotice.ends_at > now))
        .all()
    )
    return sorted(rows, key=lambda n: (NOTICE_LEVEL_ORDER.get(n.level, 9), -as_utc(n.starts_at).timestamp()))


def park_status(db, park_id: int, now: datetime | None = None, notices: list | None = None) -> dict:
    """Stato del parco per l'app. Lo calcola il backend, l'app lo mostra soltanto:
    - si contano le pratiche aperte con una categoria pubblica (quella della prima
      segnalazione collegata, o cestini/suolo per i soli sensori), mai la sicurezza;
    - 'alert' lo decide solo un avviso scritto da un operatore, mai un allarme automatico."""
    now = now or datetime.now(timezone.utc)
    practices = (
        db.query(Practice)
        .filter(Practice.park_id == park_id,
                Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress]))
        .all()
    )
    first_category = {}
    if practices:
        rows = (
            db.query(CitizenReport.practice_id, CitizenReport.category)
            .filter(CitizenReport.practice_id.in_([p.id for p in practices]))
            .order_by(CitizenReport.created_at, CitizenReport.id)
        )
        for practice_id, category in rows:
            first_category.setdefault(practice_id, category)

    counts, updated = Counter(), []
    for p in practices:
        if p.id in first_category:
            public = first_category[p.id] if first_category[p.id] != "safety" else None
        else:
            public = SENSOR_PUBLIC_CATEGORY.get(p.category)
        if public:
            counts[public] += 1
            updated.append(p.updated_at or p.created_at)

    if notices is None:
        notices = active_notices(db, park_id, now)
    levels = {n.level for n in notices}
    open_issues = sum(counts.values())
    level = "alert" if "alert" in levels else "warning" if (open_issues or "warning" in levels) else "ok"
    labels = dict(db.query(CitizenCategory.code, CitizenCategory.label))
    highlights = sorted(
        ({"category": c, "label": labels.get(c, c), "count": n} for c, n in counts.items()),
        key=lambda h: (-h["count"], h["label"]),
    )
    updated += [max(as_utc(n.created_at or n.starts_at), as_utc(n.starts_at)) for n in notices]
    return {
        "park_id": park_id,
        "level": level,
        "message": LEVEL_MESSAGES[level],
        "open_issues": open_issues,
        "updated_at": max((as_utc(u) for u in updated if u), default=as_utc(now)),
        "highlights": highlights,
    }


# Ultimo stato annunciato ai cittadini per ogni parco: (livello, id degli avvisi in corso).
# Serve a mandare park_status_changed e notice_created solo quando qualcosa cambia.
_announced: dict[int, tuple[str, frozenset]] = {}
_announced_lock = threading.Lock()
PARK_WATCH_SECONDS = 30


def refresh_park(db, park_id: int | None) -> None:
    """Ricalcola lo stato del parco e avvisa i cittadini connessi se il livello è
    cambiato o se sono iniziati avvisi nuovi. Si chiama dopo ogni modifica fatta
    dalle API; park_watch_loop copre il resto (eventi MQTT, retention, avvisi
    programmati che iniziano o scadono). Il primo calcolo fa solo da riferimento."""
    if park_id is None:
        return
    # Calcolo e confronto sotto lo stesso lock: un giro periodico e una richiesta
    # API in parallelo non devono annunciare due volte o riscrivere un livello vecchio
    with _announced_lock:
        now = datetime.now(timezone.utc)
        notices = active_notices(db, park_id, now)
        level = park_status(db, park_id, now, notices)["level"]
        current = {n.id: n for n in notices}
        previous = _announced.get(park_id)
        _announced[park_id] = (level, frozenset(current))
    if previous is None:
        return
    prev_level, prev_ids = previous
    for notice_id in sorted(current.keys() - prev_ids):
        n = current[notice_id]
        citizen_ws_manager.broadcast_from_thread({"type": "notice_created", "data": {
            "park_id": park_id, "notice_id": n.id, "title": n.title, "level": n.level,
        }})
    if level != prev_level:
        citizen_ws_manager.broadcast_from_thread({"type": "park_status_changed", "data": {"park_id": park_id, "level": level}})


def _refresh_all_parks() -> None:
    with SessionLocal() as db:
        for (park_id,) in db.query(Park.id).filter(Park.active == True).all():  # noqa: E712
            refresh_park(db, park_id)


async def park_watch_loop():
    """Task di background avviato in main.py: un giro subito (riferimento iniziale),
    poi uno ogni PARK_WATCH_SECONDS."""
    while True:
        try:
            await asyncio.to_thread(_refresh_all_parks)
        except Exception as e:
            logger.error(f"Controllo dello stato dei parchi fallito: {e}")
        await asyncio.sleep(PARK_WATCH_SECONDS)


def operator_message(practice, event, is_new: bool) -> dict:
    """Stesso messaggio che le dashboard ricevono per gli eventi dei sensori (mqtt._correlate)."""
    status = practice.status.value if hasattr(practice.status, "value") else practice.status
    if is_new:
        return {"type": "practice_created", "data": {
            "id": practice.id, "title": practice.title, "status": status,
            "severity": practice.severity, "lat": practice.lat, "lon": practice.lon,
            "zone": practice.zone, "category": practice.category,
            "created_at": str(practice.created_at),
        }}
    return {"type": "practice_updated", "data": {
        "practice_id": practice.id, "severity": practice.severity,
        "new_event": {"id": event.id, "type": "citizen", "val_number": None, "mac_address": None},
    }}
