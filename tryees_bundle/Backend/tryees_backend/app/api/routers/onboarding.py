import secrets
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, ApiKey, Device, TypeDevice, Park

router = APIRouter()

DEVICE_TYPES = {t.value: t for t in TypeDevice}


class OnboardBody(BaseModel):
    mac_address: str
    device_type: str
    zone: str
    lat: float
    lon: float
    park_id: int = 1
    label: str


class KeyUpdateBody(BaseModel):
    active: bool


@router.get("/keys")
def list_keys(db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    if current_user.type.value != 'admin':
        raise HTTPException(403)
    keys = db.query(ApiKey).order_by(ApiKey.created_at.desc()).all()
    return [_fmt_key(k) for k in keys]


@router.post("/register")
def register_device(
    body: OnboardBody,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if current_user.type.value != 'admin':
        raise HTTPException(403, "Solo admin può registrare device")

    dtype = DEVICE_TYPES.get(body.device_type)
    if not dtype:
        raise HTTPException(400, f"Tipo device non valido: {body.device_type}")

    park = db.query(Park).filter(Park.id == body.park_id).first()
    if not park:
        raise HTTPException(404, "Parco non trovato")

    existing = db.query(Device).filter(Device.mac_address == body.mac_address).first()
    if existing:
        raise HTTPException(409, f"Device {body.mac_address} già registrato")

    device = Device(
        mac_address=body.mac_address,
        zone=body.zone,
        type=dtype,
        lat=body.lat,
        lon=body.lon,
        status='ok',
    )
    db.add(device)
    db.flush()

    raw_key = f"te_{secrets.token_urlsafe(32)}"
    api_key = ApiKey(
        key=raw_key,
        device_mac=body.mac_address,
        park_id=body.park_id,
        label=body.label,
        created_by=current_user.id,
    )
    db.add(api_key)
    db.commit()
    db.refresh(api_key)

    return {
        "device": {"mac_address": device.mac_address, "zone": device.zone, "type": body.device_type},
        "api_key": raw_key,
        "mqtt_topic": f"parco/{body.mac_address}/{body.device_type}",
        "warning": "Salva questa chiave API — non sarà più visibile.",
    }


@router.delete("/keys/{key_id}")
def revoke_key(key_id: int, db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    if current_user.type.value != 'admin':
        raise HTTPException(403)
    k = db.query(ApiKey).filter(ApiKey.id == key_id).first()
    if not k: raise HTTPException(404)
    k.active = False
    db.commit()
    return {"ok": True}


@router.get("/devices")
def list_devices(db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    devices = db.query(Device).order_by(Device.zone, Device.mac_address).all()
    return [
        {
            "mac_address": d.mac_address, "zone": d.zone,
            "type": d.type.value if hasattr(d.type, 'value') else d.type,
            "lat": d.lat, "lon": d.lon, "status": d.status or "ok",
            "last_seen": d.last_seen, "notes": d.notes,
        }
        for d in devices
    ]


def _fmt_key(k):
    return {
        "id": k.id, "label": k.label, "device_mac": k.device_mac,
        "park_id": k.park_id, "active": bool(k.active),
        "created_at": k.created_at, "last_used": k.last_used,
        "key_preview": f"{k.key[:8]}...{k.key[-4:]}",
    }
