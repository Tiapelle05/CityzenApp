from datetime import datetime, timezone, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.core.config import settings
from app.api.dependencies import get_db, get_current_user, get_current_device
from app.db.models import AppUser, Device, MaintenanceLog

router = APIRouter()

# "offline" non è impostabile a mano: viene calcolato da last_seen (vedi _fmt)
MANUAL_STATUSES = ("ok", "guasto", "manutenzione")


class DeviceStatusBody(BaseModel):
    status: str
    notes: Optional[str] = None


class MaintenanceBody(BaseModel):
    action: str
    notes: Optional[str] = None


def _fmt(d):
    now = datetime.now(timezone.utc)
    threshold = now - timedelta(minutes=settings.DEVICE_OFFLINE_THRESHOLD_MIN)
    is_online = d.last_seen is not None and d.last_seen >= threshold
    raw_status = d.status or "ok"
    status = "offline" if raw_status == "ok" and not is_online else raw_status
    return {
        "mac_address": d.mac_address,
        "zone": d.zone,
        "type": d.type.value if hasattr(d.type, 'value') else d.type,
        "lat": d.lat,
        "lon": d.lon,
        "status": status,
        "raw_status": raw_status,
        "is_online": is_online,
        "notes": d.notes,
        "last_seen": d.last_seen,
        "minutes_since": int((now - d.last_seen).total_seconds() / 60) if d.last_seen else None,
    }


@router.get("/me")
def get_device_me(device: Device = Depends(get_current_device)):
    """Verifica e restituisce le informazioni del dispositivo chiamante autenticato con X-MAC-Address."""
    return _fmt(device)


@router.get("/")
def list_devices(
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    return [_fmt(d) for d in db.query(Device).order_by(Device.zone, Device.mac_address).all()]


@router.get("/faulty")
def faulty_devices(
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    all_devs = [_fmt(d) for d in db.query(Device).all()]
    return [d for d in all_devs if d["status"] != "ok"]


@router.patch("/{mac}/status")
def update_device_status(
    mac: str,
    body: DeviceStatusBody,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    d = db.query(Device).filter(Device.mac_address == mac).first()
    if not d:
        raise HTTPException(404, "Device non trovato")
    if body.status not in MANUAL_STATUSES:
        raise HTTPException(400, f"Stato non valido: usa uno tra {', '.join(MANUAL_STATUSES)}")
    old = d.status or "ok"
    d.status = body.status
    if body.notes is not None:
        d.notes = body.notes.strip() or None  # stringa vuota = cancella la nota
    db.add(MaintenanceLog(
        mac_address=mac,
        actor=current_user.username,
        action=f"status: {old} → {body.status}",
        notes=body.notes,
    ))
    db.commit()
    db.refresh(d)
    return _fmt(d)


@router.post("/{mac}/maintenance")
def add_maintenance(
    mac: str,
    body: MaintenanceBody,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if not db.query(Device).filter(Device.mac_address == mac).first():
        raise HTTPException(404, "Device non trovato")
    log = MaintenanceLog(
        mac_address=mac,
        actor=current_user.username,
        action=body.action,
        notes=body.notes,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return {"id": log.id, "mac_address": mac, "actor": log.actor, "action": log.action, "notes": log.notes, "created_at": log.created_at}


@router.delete("/{mac}")
def delete_device(
    mac: str,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if current_user.type.value != "admin":
        raise HTTPException(403, "Solo admin")
    d = db.query(Device).filter(Device.mac_address == mac).first()
    if not d:
        raise HTTPException(404, "Device non trovato")

    from app.db.models import Event
    n_events = db.query(Event).filter(Event.mac_address == mac).delete(synchronize_session=False)
    db.delete(d)  # cascade automatico su allarmi/manutenzione (FK ondelete=CASCADE)
    db.commit()
    return {"ok": True, "mac_address": mac, "deleted_events": n_events}

@router.get("/{mac}/maintenance")
def get_maintenance(
    mac: str,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    rows = (
        db.query(MaintenanceLog)
        .filter(MaintenanceLog.mac_address == mac)
        .order_by(MaintenanceLog.created_at.desc())
        .all()
    )
    return [{"id": r.id, "actor": r.actor, "action": r.action, "notes": r.notes, "created_at": r.created_at} for r in rows]
