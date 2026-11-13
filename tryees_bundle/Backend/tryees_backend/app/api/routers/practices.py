from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func
from pydantic import BaseModel, Field

from app.api.dependencies import get_db, get_current_user
from app.db.models import (
    Practice, PracticeStatus, AppUser, practice_event, Event, PracticeAudit
)
from app.services import citizen as citizen_svc
from app.services.correlation import CATEGORY_SECURITY as POLICE_CATEGORY, CATEGORY_BASKET, CATEGORY_SOIL

router = APIRouter()
# op_eco: cestini + suolo (umidità). other: solo admin
ECO_CATEGORIES = (CATEGORY_BASKET, CATEGORY_SOIL)


class StatusBody(BaseModel):
    status: PracticeStatus
    # Mostrata nell'app ai cittadini che hanno segnalato il problema: niente note interne
    citizen_note: Optional[str] = Field(None, max_length=500)


def _apply_role(q, current_user):
    if current_user.type.value == 'ente':
        q = q.filter(Practice.category == POLICE_CATEGORY)
    elif current_user.type.value == 'op_eco':
        q = q.filter(Practice.category.in_(ECO_CATEGORIES))
    return q


def _apply_category(q, category):
    """`category` accetta una o più categorie separate da virgola (es. "basket,soil")."""
    cats = [c.strip() for c in (category or "").split(",") if c.strip()]
    return q.filter(Practice.category.in_(cats)) if cats else q


def _can_access(p, current_user) -> bool:
    """Stessa regola di _apply_role, per una singola pratica."""
    t = current_user.type.value
    if t == 'ente':
        return p.category == POLICE_CATEGORY
    if t == 'op_eco':
        return p.category in ECO_CATEGORIES
    return True


def _get_accessible(db, practice_id, current_user, loader=None):
    """Pratica visibile all'utente, altrimenti 404 (non riveliamo l'esistenza di pratiche di altri ruoli)."""
    p = loader(db, practice_id) if loader else db.query(Practice).filter(Practice.id == practice_id).first()
    if not p or not _can_access(p, current_user):
        raise HTTPException(404, "Pratica non trovata")
    return p


def _fmt_event(e):
    ev_type = e.type.value if hasattr(e.type, 'value') else str(e.type)
    out = {
        "id": e.id,
        "mac_address": e.mac_address,
        "type": ev_type,
        "val_number": e.val_number,
        "sampling_time": e.sampling_time,
        "transmission_time": e.transmission_time,
        "video": None,
        "detail": None,
    }
    if e.video:
        out["video"] = {
            "video_url": e.video.video_url,
            "thumbnail_url": e.video.thumbnail_url,
            "duration_seconds": e.video.duration_seconds,
        }
    cd = getattr(e, '_camera_detail', None) or getattr(e, 'camera_detail', None)
    md = getattr(e, '_mic_detail',    None) or getattr(e, 'mic_detail', None)
    bd = getattr(e, '_basket_detail', None) or getattr(e, 'basket_detail', None)
    ld = getattr(e, '_light_detail',  None) or getattr(e, 'light_detail', None)
    sd = getattr(e, '_soil_detail',   None) or getattr(e, 'soil_detail', None)
    rp = getattr(e, '_citizen_report', None)
    if rp:
        # Segnalazione di un cittadino: testo e foto, mai l'identificativo del cittadino
        out["detail"] = {"report_code": citizen_svc.report_code(rp), "kind": rp.kind, "category": rp.category,
                         "description": rp.description, "priority": rp.priority,
                         "photo_url": citizen_svc.photo_url(rp.photo_path)}
    elif cd:
        out["detail"] = {"person_count": cd.person_count, "confidence": cd.confidence, "alert_type": cd.alert_type, "frame_url": cd.frame_url}
    elif md:
        out["detail"] = {"decibel": md.decibel, "frequency_hz": md.frequency_hz, "audio_url": md.audio_url, "alert_type": md.alert_type, "noise_db": md.noise_db}
    elif bd:
        out["detail"] = {"fill_level_pct": bd.fill_level_pct, "weight_kg": bd.weight_kg,
                          "battery_pct": bd.battery_pct, "tilt_angle": bd.tilt_angle, "fill_cm": bd.fill_cm}
    elif ld:
        out["detail"] = {"lux_value": ld.lux_value, "lux_ldr": ld.lux_ldr, "is_on": bool(ld.is_on) if ld.is_on is not None else None, "fault_code": ld.fault_code}
    elif sd:
        out["detail"] = {"humidity_pct": sd.humidity_pct, "temperature_c": sd.temperature_c, "ph": sd.ph,
                         "pm25": sd.pm25, "pm10": sd.pm10, "soil_humidity_pct": sd.soil_humidity_pct}
    return out


def _load_practice(db, practice_id):
    from app.db.models import EventCamera, EventMicrophone, EventBasket, EventLight, EventSoil, EventCitizen, CitizenReport
    p = (
        db.query(Practice)
        .options(joinedload(Practice.events).joinedload(Event.video))
        .filter(Practice.id == practice_id)
        .first()
    )
    if not p or not p.events:
        return p
    # Bulk load polymorphic details in 5 queries instead of 5 * N queries
    event_ids = [e.id for e in p.events]
    cameras = {c.event_id: c for c in db.query(EventCamera).filter(EventCamera.event_id.in_(event_ids)).all()}
    mics    = {m.event_id: m for m in db.query(EventMicrophone).filter(EventMicrophone.event_id.in_(event_ids)).all()}
    baskets = {b.event_id: b for b in db.query(EventBasket).filter(EventBasket.event_id.in_(event_ids)).all()}
    lights  = {l.event_id: l for l in db.query(EventLight).filter(EventLight.event_id.in_(event_ids)).all()}
    soils   = {s.event_id: s for s in db.query(EventSoil).filter(EventSoil.event_id.in_(event_ids)).all()}
    reports = {
        ev_id: r for ev_id, r in db.query(EventCitizen.event_id, CitizenReport)
        .join(CitizenReport, CitizenReport.id == EventCitizen.report_id)
        .filter(EventCitizen.event_id.in_(event_ids)).all()
    }
    for e in p.events:
        e._camera_detail = cameras.get(e.id)
        e._mic_detail    = mics.get(e.id)
        e._basket_detail = baskets.get(e.id)
        e._light_detail  = lights.get(e.id)
        e._soil_detail   = soils.get(e.id)
        e._citizen_report = reports.get(e.id)
    return p


def _fmt_practice(p, db=None):
    result = {
        "id": p.id,
        "title": p.title,
        "status": p.status.value if hasattr(p.status, 'value') else p.status,
        "severity": p.severity,
        "category": p.category,
        "lat": p.lat,
        "lon": p.lon,
        "zone": p.zone,
        "incident_id": p.incident_id,
        "created_at": p.created_at,
        "updated_at": p.updated_at,
        "resolved_at": p.resolved_at,
        "events": [_fmt_event(e) for e in (p.events or [])],
        "actuators": [],
    }
    if db is not None:
        result["actuators"] = _fmt_actuators(p, db)
    return result


def _fmt_actuators(p, db):
    """Riepilogo di cosa si è attivato (sirena/LED) in seguito a questa
    pratica: sia allarmi sullo stesso device (vandalismo/affollamento),
    sia il broadcast al modellino quando l'origine è la telecamera reale
    (in quel caso il device_id dell'allarme è del modellino, non della
    telecamera — si aggancia per finestra temporale)."""
    from app.db.models import EventAlarm
    from sqlalchemy import or_, and_
    mac_addresses = {e.mac_address for e in (p.events or []) if e.mac_address}
    if not mac_addresses:
        return []
    window_end = p.resolved_at or datetime.now(timezone.utc)
    broadcast_window_end = p.created_at + timedelta(seconds=10)
    rows = (
        db.query(EventAlarm)
        .filter(or_(
            and_(EventAlarm.device_id.in_(mac_addresses),
                 EventAlarm.timestamp >= p.created_at, EventAlarm.timestamp <= window_end),
            and_(EventAlarm.alarm_type.like("TELECAMERA_%"),
                 EventAlarm.timestamp >= p.created_at, EventAlarm.timestamp <= broadcast_window_end),
        ))
        .order_by(EventAlarm.timestamp.asc())
        .all()
    )
    return [
        {"device_id": a.device_id, "alarm_type": a.alarm_type,
         "sirena_active": bool(a.sirena_active), "led_police_active": bool(a.led_police_active),
         "resolved": bool(a.resolved), "timestamp": a.timestamp}
        for a in rows
    ]


@router.websocket("/ws")
async def practices_ws(websocket: WebSocket, token: Optional[str] = Query(None)):
    """Aggiornamenti live per la dashboard. Richiede il JWT in query (?token=…),
    perché i browser non permettono header custom sul WebSocket."""
    from app.core.ws_manager import ws_manager
    from app.api.dependencies import user_from_token
    from app.db.database import SessionLocal
    db = SessionLocal()
    try:
        user = user_from_token(token, db)
    finally:
        db.close()
    if user is None:
        # accept + close 1008: il client riceve un codice esplicito e non riprova all'infinito
        await websocket.accept()
        await websocket.close(code=1008)
        return
    await ws_manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)


@router.get("/overview/severity")
def severity_overview(
    category: Optional[str] = Query(None, max_length=64),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    q = db.query(
        Practice.status,
        func.count(Practice.id).label("count"),
        func.avg(Practice.severity).label("avg_severity"),
        func.max(Practice.severity).label("max_severity"),
    )
    q = _apply_role(q, current_user)
    q = _apply_category(q, category)
    q = q.group_by(Practice.status)
    return [
        {
            "status": r.status.value if hasattr(r.status, 'value') else r.status,
            "count": r.count,
            "avg_severity": round(r.avg_severity or 0, 2),
            "max_severity": round(r.max_severity or 0, 2),
        }
        for r in q.all()
    ]


@router.get("/")
def list_practices(
    status: Optional[PracticeStatus] = None,
    min_severity: Optional[float] = Query(None, ge=0.0, le=10.0),
    category: Optional[str] = Query(None, max_length=64),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    q = db.query(Practice)
    q = _apply_role(q, current_user)
    if status:
        q = q.filter(Practice.status == status)
    if min_severity is not None:
        q = q.filter(Practice.severity >= min_severity)
    q = _apply_category(q, category)
    practices = q.order_by(Practice.updated_at.desc()).offset(skip).limit(limit).all()
    practice_ids = [p.id for p in practices]
    counts = dict(
        db.query(practice_event.c.practice_id, func.count(practice_event.c.event_id))
        .filter(practice_event.c.practice_id.in_(practice_ids))
        .group_by(practice_event.c.practice_id)
        .all()
    ) if practice_ids else {}
    result = []
    for p in practices:
        count = counts.get(p.id, 0)
        result.append({
            "id": p.id,
            "title": p.title,
            "status": p.status.value if hasattr(p.status, 'value') else p.status,
            "severity": p.severity,
            "category": p.category,
            "lat": p.lat,
            "lon": p.lon,
            "zone": p.zone,
            "incident_id": p.incident_id,
            "created_at": p.created_at,
            "updated_at": p.updated_at,
            "event_count": count,
        })
    return result


@router.get("/{practice_id}/audit")
def get_audit(
    practice_id: int,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _get_accessible(db, practice_id, current_user)
    rows = (
        db.query(PracticeAudit)
        .filter(PracticeAudit.practice_id == practice_id)
        .order_by(PracticeAudit.created_at.asc())
        .all()
    )
    return [
        {"id": r.id, "actor": r.actor, "action": r.action, "detail": r.detail, "created_at": r.created_at}
        for r in rows
    ]


@router.post("/{practice_id}/escalate")
def escalate(
    practice_id: int,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = _get_accessible(db, practice_id, current_user, loader=_load_practice)
    db.add(PracticeAudit(
        practice_id=p.id,
        actor=current_user.username,
        action="escalation",
        detail=f"Escalation da {current_user.username}",
    ))
    db.commit()
    fmt = _fmt_practice(p, db)
    fmt["escalated_by"] = current_user.username
    fmt["escalated_at"] = str(datetime.now(timezone.utc))
    fmt["event_count"] = len(p.events or [])
    fmt["media"] = [
        {"video_url": e.video.video_url, "thumbnail_url": e.video.thumbnail_url}
        for e in (p.events or []) if e.video
    ]
    return fmt


@router.post("/{practice_id}/archive")
def archive_practice(
    practice_id: int,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = _get_accessible(db, practice_id, current_user)
    p.status = PracticeStatus.closed
    p.updated_at = datetime.now(timezone.utc)
    p.resolved_at = p.resolved_at or datetime.now(timezone.utc)
    db.add(PracticeAudit(
        practice_id=p.id,
        actor=current_user.username,
        action="archived",
        detail="Pratica archiviata",
    ))
    db.commit()
    citizen_svc.sync_reports(db, p)
    citizen_svc.refresh_park(db, p.park_id)
    from app.core.ws_manager import ws_manager
    ws_manager.broadcast_from_thread({
        "type": "practice_updated",
        "data": {"practice_id": p.id, "status": PracticeStatus.closed.value},
    })
    return {"ok": True}


@router.delete("/{practice_id}")
def delete_practice(
    practice_id: int,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.type.value != "admin":
        raise HTTPException(403, "Solo admin può eliminare una pratica")
    p = db.query(Practice).filter(Practice.id == practice_id).first()
    if not p:
        raise HTTPException(404, "Pratica non trovata")
    closed_reports = citizen_svc.detach_reports(db, [p.id])
    park_id = p.park_id
    db.delete(p)
    db.commit()
    citizen_svc.notify_reports(closed_reports)
    citizen_svc.refresh_park(db, park_id)
    return {"ok": True}


@router.get("/{practice_id}")
def get_practice(
    practice_id: int,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = _get_accessible(db, practice_id, current_user, loader=_load_practice)
    return _fmt_practice(p, db)


@router.patch("/{practice_id}/status")
def update_status(
    practice_id: int,
    body: StatusBody,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = _get_accessible(db, practice_id, current_user)
    old_status = p.status.value if hasattr(p.status, 'value') else str(p.status)
    p.status = body.status
    p.updated_at = datetime.now(timezone.utc)
    if body.status in (PracticeStatus.resolved, PracticeStatus.closed):
        p.resolved_at = datetime.now(timezone.utc)
    db.add(PracticeAudit(
        practice_id=p.id,
        actor=current_user.username,
        action="status_change",
        detail=f"{old_status} → {body.status.value}",
    ))
    db.commit()
    citizen_svc.sync_reports(db, p, note=(body.citizen_note or "").strip() or None)
    citizen_svc.refresh_park(db, p.park_id)
    from app.core.ws_manager import ws_manager
    ws_manager.broadcast_from_thread({
        "type": "practice_updated",
        "data": {"practice_id": p.id, "status": body.status.value},
    })
    return _fmt_practice(_load_practice(db, practice_id), db)
