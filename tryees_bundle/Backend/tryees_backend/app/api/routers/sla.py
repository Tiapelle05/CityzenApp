from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.core.config import settings
from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, Device, Event, Practice, PracticeStatus, AccessLog

router = APIRouter()

OFFLINE_THRESHOLD_MIN = settings.DEVICE_OFFLINE_THRESHOLD_MIN


@router.get("/")
def system_health(
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    threshold = now - timedelta(minutes=OFFLINE_THRESHOLD_MIN)

    total_devices = db.query(func.count(Device.mac_address)).scalar()

    online_devices = db.query(func.count(Device.mac_address)).filter(
        Device.last_seen >= threshold
    ).scalar()

    faulty_devices = db.query(func.count(Device.mac_address)).filter(
        Device.status != 'ok'
    ).scalar()

    events_last_hour = db.query(func.count(Event.id)).filter(
        Event.transmission_time >= now - timedelta(hours=1)
    ).scalar()

    events_last_24h = db.query(func.count(Event.id)).filter(
        Event.transmission_time >= now - timedelta(hours=24)
    ).scalar()

    open_practices = db.query(func.count(Practice.id)).filter(
        Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress])
    ).scalar()

    critical_practices = db.query(func.count(Practice.id)).filter(
        Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress]),
        Practice.severity >= 7,
    ).scalar()

    failed_logins_24h = db.query(func.count(AccessLog.id)).filter(
        AccessLog.success == False,  # noqa: E712
        AccessLog.created_at >= now - timedelta(hours=24),
    ).scalar()

    offline_devices = db.query(Device).filter(
        (Device.last_seen < threshold) | Device.last_seen.is_(None)
    ).all()

    return {
        "timestamp": now,
        "devices": {
            "total": total_devices,
            "online": online_devices,
            "offline": total_devices - online_devices,
            "faulty": faulty_devices,
            "offline_list": [
                {
                    "mac_address": d.mac_address,
                    "zone": d.zone,
                    "type": d.type.value if hasattr(d.type, 'value') else d.type,
                    "last_seen": d.last_seen,
                    "minutes_since": int((now - d.last_seen).total_seconds() / 60) if d.last_seen else None,
                }
                for d in offline_devices
            ],
        },
        "events": {
            "last_hour": events_last_hour,
            "last_24h": events_last_24h,
        },
        "practices": {
            "open": open_practices,
            "critical": critical_practices,
        },
        "security": {
            "failed_logins_24h": failed_logins_24h,
        },
        "status": "degraded" if (total_devices - online_devices) > total_devices * 0.3 else "ok",
    }


@router.get("/devices")
def device_health(
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    threshold = now - timedelta(minutes=OFFLINE_THRESHOLD_MIN)
    devices = db.query(Device).order_by(Device.zone, Device.mac_address).all()
    since = now - timedelta(hours=24)
    counts = dict(
        db.query(Event.mac_address, func.count(Event.id))
        .filter(Event.transmission_time >= since)
        .group_by(Event.mac_address)
        .all()
    )

    result = []
    for d in devices:
        events_24h = counts.get(d.mac_address, 0)

        is_online = d.last_seen is not None and d.last_seen >= threshold
        result.append({
            "mac_address": d.mac_address,
            "zone": d.zone,
            "type": d.type.value if hasattr(d.type, 'value') else d.type,
            "status": d.status or "ok",
            "is_online": is_online,
            "last_seen": d.last_seen,
            "events_24h": events_24h,
            "minutes_since": int((now - d.last_seen).total_seconds() / 60) if d.last_seen else None,
        })
    return result


@router.get("/access-log")
def access_log(
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if current_user.type.value != 'admin':
        from fastapi import HTTPException
        raise HTTPException(403)
    rows = db.query(AccessLog).order_by(AccessLog.created_at.desc()).limit(limit).all()
    return [
        {"id": r.id, "username": r.username, "action": r.action, "ip": r.ip, "success": bool(r.success), "created_at": r.created_at}
        for r in rows
    ]
