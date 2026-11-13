"""
Router consumi elettrici (Watt/kWh) — legge le letture EventPower salvate da
mqtt.py per device di tipo ESP32/Orange Pi/server dotati di sensore di
corrente in linea (INA219/INA226) o presa smart.

  GET /power/latest        -> ultima lettura per ogni device che ha mai mandato dati power
  GET /power/history       -> serie storica di un device (per grafico)
  GET /power/daily         -> kWh per giorno di un device, integrando le letture nel tempo
"""

from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, Device, Event

router = APIRouter()


def _integrate_kwh(readings):
    """readings: lista di (timestamp, power_w) ordinata per timestamp.
    Integrazione trapezoidale: area tra due letture consecutive = potenza
    media * durata in ore, sommata su tutto l'intervallo, convertita in kWh."""
    if len(readings) < 2:
        return 0.0
    total_wh = 0.0
    for (t1, p1), (t2, p2) in zip(readings, readings[1:]):
        hours = (t2 - t1).total_seconds() / 3600
        if hours <= 0 or hours > 6:  # scarta buchi enormi (device spento/riavviato)
            continue
        total_wh += ((p1 + p2) / 2) * hours
    return round(total_wh / 1000, 3)


@router.get("/latest")
def latest_power(db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    devices = db.query(Device).all()
    out = []
    for d in devices:
        last_ev = (
            db.query(Event)
            .filter(Event.mac_address == d.mac_address, Event.type == "power")
            .order_by(Event.transmission_time.desc())
            .first()
        )
        power = getattr(last_ev, "power_detail", None) if last_ev else None
        if not power:
            continue
        out.append({
            "mac_address": d.mac_address, "type": d.type.value if hasattr(d.type, 'value') else d.type,
            "zone": d.zone, "voltage": power.voltage, "current_ma": power.current_ma,
            "power_w": power.power_w, "timestamp": last_ev.transmission_time.isoformat() if last_ev.transmission_time else None,
        })
    return out


@router.get("/history")
def power_history(
    mac: str = Query(...), hours: int = Query(24, ge=1, le=24 * 30),
    db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user),
):
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    rows = (
        db.query(Event)
        .filter(Event.mac_address == mac, Event.type == "power", Event.transmission_time >= since)
        .order_by(Event.transmission_time.asc())
        .all()
    )
    return [
        {"timestamp": e.transmission_time.isoformat() if e.transmission_time else None,
         "voltage": e.power_detail.voltage, "current_ma": e.power_detail.current_ma, "power_w": e.power_detail.power_w}
        for e in rows if e.power_detail
    ]


@router.get("/daily")
def power_daily(
    mac: str = Query(...), days: int = Query(7, ge=1, le=90),
    db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user),
):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = (
        db.query(Event)
        .filter(Event.mac_address == mac, Event.type == "power", Event.transmission_time >= since)
        .order_by(Event.transmission_time.asc())
        .all()
    )
    readings = [(e.transmission_time, e.power_detail.power_w) for e in rows if e.power_detail and e.power_detail.power_w is not None]

    by_day = {}
    for t, p in readings:
        by_day.setdefault(t.date().isoformat(), []).append((t, p))

    return [{"date": day, "kwh": _integrate_kwh(vals)} for day, vals in sorted(by_day.items())]
