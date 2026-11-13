"""
Mini dashboard del modellino/miniparco: una pagina HTML/JS autonoma, semplice
e senza fronzoli, con aggiornamento in tempo reale via SSE.

Endpoint:
  GET  /mini              -> pagina HTML
  GET  /mini/state        -> stato corrente sensori + allarmi attivi (JSON)
  GET  /mini/stream       -> Server-Sent Events, stesso payload di /mini/state ogni 2s
  GET  /mini/alarms       -> storico allarmi (event_alarm)
  POST /mini/alarms/{id}/reset -> riarma un allarme (spegne sirena/LED)
  GET  /mini/videos       -> elenco video mock salvati
  POST /mini/test-trigger -> Admin: pubblica un evento di test sul broker MQTT
                             (stesso identico percorso di un evento reale,
                             solo Admin, usato dai pulsanti del digital twin)
  POST /mini/reset        -> Admin: cancella eventi/allarmi/pratiche del
                             modellino (zone A/B + cestino), device restano registrati
  GET  /mini/settings     -> soglie automazioni correnti
  PUT  /mini/settings     -> Admin: aggiorna una o più soglie
  GET  /mini/commands     -> storico comandi MQTT inviati agli attuatori
"""

import asyncio
import json
import logging
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.config import settings
from app.api.dependencies import get_db, get_current_user
from app.core.mqtt import mqtt_manager, get_settings, DEFAULT_SETTINGS
from app.db.database import SessionLocal
from app.db.models import AppUser, Device, Event, EventAlarm, MiniVideoLog

logger = logging.getLogger(__name__)
router = APIRouter()

MINI_DEVICE_TYPES = ("mini_ambiente", "mini_varchi", "mini_bin", "mini_display", "mini_node")


def _build_state(db: Session) -> dict:
    now = datetime.now(timezone.utc)
    threshold = now - timedelta(minutes=settings.DEVICE_OFFLINE_THRESHOLD_MIN)

    devices = (
        db.query(Device)
        .filter(Device.type.in_(MINI_DEVICE_TYPES) | (
            (Device.type == "camera") & (Device.zone.ilike("%zona a%") | Device.zone.ilike("%zona b%"))
        ))
        .all()
    )

    sensors = []
    for d in devices:
        dtype = d.type.value if hasattr(d.type, "value") else d.type

        if dtype == "mini_node":
            # nodo combinato: prende l'ultima lettura di ciascuna categoria separatamente
            reading = {}
            last_soil = (db.query(Event).filter(Event.mac_address == d.mac_address, Event.type == "humidity")
                         .order_by(Event.transmission_time.desc()).first())
            if last_soil and getattr(last_soil, "soil_detail", None):
                s = last_soil.soil_detail
                reading.update({"temperatura_c": s.temperature_c, "umidita_pct": s.humidity_pct,
                                "umidita_suolo_pct": s.soil_humidity_pct, "pm25": s.pm25})
            last_bin = (db.query(Event).filter(Event.mac_address == d.mac_address, Event.type == "full")
                        .order_by(Event.transmission_time.desc()).first())
            if last_bin and getattr(last_bin, "basket_detail", None):
                b = last_bin.basket_detail
                reading.update({"riempimento_pct": b.fill_level_pct, "inclinazione_deg": b.tilt_angle})
            last_varco = (db.query(Event).filter(Event.mac_address == d.mac_address, Event.type.in_(["ingresso", "uscita"]))
                          .order_by(Event.transmission_time.desc()).first())
            if last_varco:
                reading["ultimo_varco"] = last_varco.type.value if hasattr(last_varco.type, "value") else last_varco.type
            last_ev = last_soil or last_bin or last_varco
            reading = reading or None
        else:
            last_ev = (
                db.query(Event)
                .filter(Event.mac_address == d.mac_address)
                .order_by(Event.transmission_time.desc())
                .first()
            )
            reading = None
            if last_ev:
                if dtype == "mini_ambiente":
                    last_soil_ev = (
                        db.query(Event)
                        .filter(Event.mac_address == d.mac_address, Event.type == "humidity")
                        .order_by(Event.transmission_time.desc()).first()
                    )
                    soil = getattr(last_soil_ev, "soil_detail", None) if last_soil_ev else None
                    if soil:
                        reading = {"temperatura_c": soil.temperature_c, "umidita_pct": soil.humidity_pct,
                                   "umidita_suolo_pct": soil.soil_humidity_pct, "pm25": soil.pm25, "pm10": soil.pm10}
                elif dtype == "mini_bin":
                    basket = getattr(last_ev, "basket_detail", None)
                    if basket:
                        reading = {"riempimento_pct": basket.fill_level_pct, "inclinazione_deg": basket.tilt_angle}
                elif dtype == "mini_varchi":
                    reading = {"ultimo_evento": last_ev.type.value if hasattr(last_ev.type, "value") else last_ev.type}
                elif dtype == "camera":
                    cam = getattr(last_ev, "camera_detail", None)
                    if cam:
                        reading = {"ultimo_alert": cam.alert_type, "confidenza": cam.confidence}

        is_online = d.last_seen is not None and d.last_seen >= threshold
        sensors.append({
            "device_id": d.mac_address,
            "zone": d.zone,
            "type": d.type.value if hasattr(d.type, "value") else d.type,
            "buzzer_active": bool(d.buzzer_active),
            "last_seen": d.last_seen.isoformat() if d.last_seen else None,
            "is_online": is_online,
            "minutes_since": int((now - d.last_seen).total_seconds() / 60) if d.last_seen else None,
            "reading": reading,
        })

    active_alarms = (
        db.query(EventAlarm)
        .filter(EventAlarm.resolved == False)  # noqa: E712
        .order_by(EventAlarm.timestamp.desc())
        .all()
    )

    return {
        "sensors": sensors,
        "active_alarms": [
            {"id": a.id, "device_id": a.device_id, "alarm_type": a.alarm_type,
             "sirena_active": bool(a.sirena_active), "led_police_active": bool(a.led_police_active),
             "timestamp": a.timestamp.isoformat() if a.timestamp else None}
            for a in active_alarms
        ],
    }


@router.post("/reset")
def reset_mini_data(current_user: AppUser = Depends(get_current_user), db: Session = Depends(get_db)):
    """Cancella tutti i dati generati dal modellino (letture ambientali,
    allarmi, pratiche) — device e loro registrazione restano intatti."""
    if current_user.type.value != "admin":
        raise HTTPException(403, "Solo admin")
    from app.db.models import Practice

    devices = (
        db.query(Device)
        .filter(Device.type.in_(MINI_DEVICE_TYPES) | (
            (Device.type == "camera") & (Device.zone.ilike("%zona a%") | Device.zone.ilike("%zona b%"))
        ))
        .all()
    )
    macs = [d.mac_address for d in devices]
    if not macs:
        return {"ok": True, "deleted_events": 0, "deleted_alarms": 0, "deleted_practices": 0}

    practice_ids = [
        pid for (pid,) in db.query(Practice.id).join(Practice.events).filter(Event.mac_address.in_(macs)).distinct().all()
    ]

    n_events  = db.query(Event).filter(Event.mac_address.in_(macs)).delete(synchronize_session=False)
    n_alarms  = db.query(EventAlarm).filter(EventAlarm.device_id.in_(macs)).delete(synchronize_session=False)

    n_practices = 0
    if practice_ids:
        n_practices = (
            db.query(Practice)
            .filter(Practice.id.in_(practice_ids), ~Practice.events.any())
            .delete(synchronize_session=False)
        )

    for d in devices:
        d.buzzer_active = False
        d.buzzer_triggered_at = None

    db.commit()
    logger.info(f"[Mini-reset] {len(macs)} device, {n_events} eventi, {n_alarms} allarmi, {n_practices} pratiche (admin: {current_user.username})")
    return {"ok": True, "deleted_events": n_events, "deleted_alarms": n_alarms, "deleted_practices": n_practices}



@router.get("/state")
def get_state(db: Session = Depends(get_db)):
    return _build_state(db)


@router.get("/settings")
def get_mini_settings(db: Session = Depends(get_db)):
    return {"values": get_settings(db), "defaults": DEFAULT_SETTINGS}


class SettingsUpdate(BaseModel):
    vandal_tilt_deg: float | None = None
    bin_full_pct: float | None = None
    crowd_threshold: int | None = None
    presence_light_seconds: int | None = None


@router.put("/settings")
def update_mini_settings(body: SettingsUpdate, current_user: AppUser = Depends(get_current_user), db: Session = Depends(get_db)):
    if current_user.type.value != "admin":
        raise HTTPException(403, "Solo admin")
    from app.db.models import Setting
    import app.core.mqtt as mqtt_module

    updates = body.dict(exclude_none=True)
    for key, value in updates.items():
        row = db.query(Setting).filter(Setting.key == key).first()
        if row:
            row.value = str(value)
        else:
            db.add(Setting(key=key, value=str(value)))
    db.commit()
    mqtt_module._settings_cache_ts = 0  # forza il refresh della cache al prossimo evento
    return {"values": get_settings(db), "defaults": DEFAULT_SETTINGS}


@router.get("/commands")
def list_command_log(limit: int = 50, db: Session = Depends(get_db)):
    from app.db.models import CommandLog
    rows = db.query(CommandLog).order_by(CommandLog.created_at.desc()).limit(limit).all()
    return [
        {"id": c.id, "topic": c.topic, "payload": json.loads(c.payload), "created_at": c.created_at.isoformat() if c.created_at else None}
        for c in rows
    ]


@router.get("/alarms")
def list_alarms(resolved: bool | None = None, limit: int = 50, db: Session = Depends(get_db)):
    q = db.query(EventAlarm)
    if resolved is not None:
        q = q.filter(EventAlarm.resolved == resolved)
    rows = q.order_by(EventAlarm.timestamp.desc()).limit(limit).all()
    return [
        {"id": a.id, "device_id": a.device_id, "alarm_type": a.alarm_type,
         "sirena_active": bool(a.sirena_active), "led_police_active": bool(a.led_police_active),
         "resolved": bool(a.resolved), "timestamp": a.timestamp.isoformat() if a.timestamp else None,
         "resolved_at": a.resolved_at.isoformat() if a.resolved_at else None}
        for a in rows
    ]


@router.post("/alarms/{alarm_id}/reset")
def reset_alarm(alarm_id: int, db: Session = Depends(get_db)):
    alarm = db.query(EventAlarm).filter(EventAlarm.id == alarm_id).first()
    if not alarm:
        raise HTTPException(404, "Allarme non trovato")
    mqtt_manager.reset_alarm(db, alarm)
    return {"ok": True, "id": alarm.id}


@router.get("/videos")
def list_videos(limit: int = 50, db: Session = Depends(get_db)):
    rows = db.query(MiniVideoLog).order_by(MiniVideoLog.timestamp.desc()).limit(limit).all()
    return [
        {"id": v.id, "device_id": v.device_id, "video_path": v.video_path,
         "trigger_event": v.trigger_event, "timestamp": v.timestamp.isoformat() if v.timestamp else None}
        for v in rows
    ]


@router.get("/env-history")
def env_history(limit: int = 20, db: Session = Depends(get_db)):
    """Ultime N letture ambientali (Zona B: temperatura/umidità/PM2.5), per
    il pannello in tempo reale della dashboard modellino."""
    device = db.query(Device).filter(
        Device.type.in_(("mini_node", "mini_ambiente")), Device.zone.ilike("%zona b%")
    ).first()
    if not device:
        return []
    rows = (
        db.query(Event)
        .filter(Event.mac_address == device.mac_address, Event.type == "humidity")
        .order_by(Event.transmission_time.desc())
        .limit(limit)
        .all()
    )
    out = []
    for ev in rows:
        soil = getattr(ev, "soil_detail", None)
        if not soil:
            continue
        out.append({
            "timestamp": ev.transmission_time.isoformat() if ev.transmission_time else None,
            "temperature_c": soil.temperature_c,
            "humidity_pct": soil.humidity_pct,
            "soil_humidity_pct": soil.soil_humidity_pct,
            "pm25": soil.pm25,
            "pm10": soil.pm10,
        })
    out.reverse()  # dal più vecchio al più recente, comodo per un grafico
    return out


@router.get("/practices")
def list_mini_practices(limit: int = 50, db: Session = Depends(get_db)):
    """Storico pratiche generate dai device del modellino (separato dallo
    storico allarmi tecnico di /mini/alarms — qui sono le pratiche 'alto
    livello', le stesse che vede la dashboard Polizia)."""
    from app.db.models import Practice, Event
    mac_addresses = [d.mac_address for d in db.query(Device).filter(Device.type.in_(MINI_DEVICE_TYPES)).all()]
    if not mac_addresses:
        return []
    rows = (
        db.query(Practice)
        .join(Practice.events)
        .filter(Event.mac_address.in_(mac_addresses))
        .distinct()
        .order_by(Practice.created_at.desc())
        .limit(limit)
        .all()
    )
    return [
        {"id": p.id, "title": p.title, "status": p.status.value if hasattr(p.status, "value") else p.status,
         "severity": p.severity, "category": p.category, "zone": p.zone,
         "created_at": p.created_at.isoformat() if p.created_at else None,
         "resolved_at": p.resolved_at.isoformat() if p.resolved_at else None}
        for p in rows
    ]


# Etichette del menu telecamera nel digital twin -> alert_type reale nel sistema
CAMERA_TEST_LABELS = {
    "oggetto_pericoloso": "arma",
    "segnale_aiuto": "segnale_aiuto",
    "aggressione": "rissa",
}


class TestTriggerBody(BaseModel):
    kind: str            # "camera_alert" | "ultrasonic" | "bin" | "environment"
    zone: str | None = None       # "a" | "b" — richiesto per camera_alert/ultrasonic
    alert_type: str | None = None  # solo per camera_alert: una chiave di CAMERA_TEST_LABELS
    temperature_c: float | None = None
    humidity_pct: float | None = None
    pm25: float | None = None
    fill_level_pct: float | None = None   # solo per kind "bin": % riempimento cestino
    tilt_angle_deg: float | None = None   # solo per kind "bin": inclinazione (ribaltamento)


def _find_device(db: Session, dtype_in: tuple, zone_needle: str | None):
    q = db.query(Device).filter(Device.type.in_(dtype_in))
    if zone_needle:
        q = q.filter(Device.zone.ilike(f"%{zone_needle}%"))
    return q.first()


def _last_reading_values(db: Session, device: Device):
    """Ultimi valori ambientali noti per quel device, per il pulsante
    'manda un dato simile all'ultimo' quando l'operatore non ne specifica di nuovi."""
    last = (
        db.query(Event)
        .filter(Event.mac_address == device.mac_address, Event.type == "humidity")
        .order_by(Event.transmission_time.desc())
        .first()
    )
    soil = getattr(last, "soil_detail", None) if last else None
    if soil:
        return soil.temperature_c, soil.humidity_pct, soil.pm25
    return 22.0, 55.0, 12.0  # default ragionevole se non è mai arrivato nulla


@router.post("/test-trigger")
def test_trigger(body: TestTriggerBody, db: Session = Depends(get_db),
                  current_user: AppUser = Depends(get_current_user)):
    """Pulsanti del digital twin: pubblica un evento sul broker MQTT esattamente
    come farebbe l'hardware vero — stesso topic, stesso payload, stessa pipeline
    di arricchimento/automazioni/pratica. Solo Admin."""
    if current_user.type.value != "admin":
        raise HTTPException(403, "Solo un amministratore può usare i pulsanti di test")

    if body.kind == "camera_alert":
        if body.zone not in ("a", "b"):
            raise HTTPException(400, "zone deve essere 'a' o 'b'")
        alert_type = CAMERA_TEST_LABELS.get(body.alert_type or "")
        if not alert_type:
            raise HTTPException(400, f"alert_type deve essere una tra: {list(CAMERA_TEST_LABELS)}")
        device = _find_device(db, ("camera",), f"zona {body.zone}") or _find_device(db, ("mini_node", "mini_ambiente"), f"zona {body.zone}")
        if not device:
            raise HTTPException(404, f"Nessuna telecamera registrata per la zona {body.zone.upper()}")
        payload = {"device_id": device.mac_address, "type": "alert", "val_number": 1, "alert_type": alert_type, "confidence": 0.95}

    elif body.kind == "ultrasonic":
        if body.zone not in ("a", "b"):
            raise HTTPException(400, "zone deve essere 'a' o 'b'")
        device = _find_device(db, ("mini_node", "mini_varchi", "mini_ambiente"), f"zona {body.zone}")
        if not device:
            raise HTTPException(404, f"Nessun nodo registrato per la zona {body.zone.upper()}")
        payload = {"device_id": device.mac_address, "ingresso": True, "presence": True}

    elif body.kind == "bin":
        # Cestino smart: riempimento e/o inclinazione arbitrari. I default
        # riproducono uno scenario "pieno"; passando fill_level_pct/tilt_angle_deg
        # si simulano svuotamento (fill basso), ribaltamento (tilt alto), ecc.
        # Sono le automazioni lato backend (soglie bin_full_pct / vandal_tilt_deg)
        # a decidere se accendere il LED rosso o far scattare l'allarme vandalismo.
        device = _find_device(db, ("mini_bin", "mini_node"), "cestino") or _find_device(db, ("mini_bin", "mini_node"), None)
        if not device:
            raise HTTPException(404, "Nessun nodo cestino registrato")
        fill = body.fill_level_pct if body.fill_level_pct is not None else 90.0
        tilt = body.tilt_angle_deg if body.tilt_angle_deg is not None else 2.0
        payload = {"device_id": device.mac_address, "full": fill, "fill_level_pct": fill, "tilt_angle": tilt}

    elif body.kind == "environment":
        device = _find_device(db, ("mini_node", "mini_ambiente", "mini_varchi"), "zona b")
        if not device:
            raise HTTPException(404, "Nessun nodo con sensori ambiente registrato in Zona B")
        last_temp, last_hum, last_pm25 = _last_reading_values(db, device)
        payload = {
            "device_id": device.mac_address,
            "temperature_c": body.temperature_c if body.temperature_c is not None else last_temp,
            "humidity_pct": body.humidity_pct if body.humidity_pct is not None else last_hum,
            "pm25": body.pm25 if body.pm25 is not None else last_pm25,
        }
        payload["humidity"] = payload["humidity_pct"]  # fa nascere l'evento lato backend

    else:
        raise HTTPException(400, f"kind sconosciuto: {body.kind}")

    mqtt_manager.client.publish(f"parco/{device.mac_address}/events", json.dumps(payload), qos=1)
    logger.info(f"[Test-trigger] {body.kind} su {device.mac_address} (admin: {current_user.username})")
    return {"ok": True, "device_id": device.mac_address, "payload": payload}


@router.get("/stream")
async def stream():
    async def gen():
        while True:
            try:
                with SessionLocal() as db:
                    yield f"data: {json.dumps(_build_state(db), default=str)}\n\n"
            except Exception as e:
                logger.error(f"SSE error: {e}")
            await asyncio.sleep(2)
    # X-Accel-Buffering: nginx inoltra ogni aggiornamento subito invece di accumularli
    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.get("", response_class=HTMLResponse)
def mini_page():
    return HTMLResponse(_PAGE_HTML)


# Pagina statica: HTML/CSS/JS semplice, niente framework, niente
# librerie esterne. Stile volutamente essenziale: font di sistema,
# bordi sottili, nessun gradiente/ombra/neon.
_PAGE_HTML = """<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<title>Modellino - Pannello di controllo</title>
<style>
  * { box-sizing: border-box; }
  body {
    font-family: Arial, Helvetica, sans-serif;
    background: #f4f4f4;
    color: #222;
    margin: 0;
    padding: 20px;
  }
  h1 { font-size: 18px; margin: 0 0 4px 0; }
  h2 { font-size: 14px; margin: 24px 0 8px 0; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
  .sub { color: #666; font-size: 12px; margin-bottom: 16px; }
  table { width: 100%; border-collapse: collapse; background: #fff; }
  th, td { text-align: left; padding: 6px 8px; border: 1px solid #ddd; font-size: 13px; }
  th { background: #eee; }
  .status-ok   { color: #2a7a2a; font-weight: bold; }
  .status-off  { color: #999; }
  .status-warn { color: #b33; font-weight: bold; }
  .alarm-box {
    background: #fff3f3;
    border: 1px solid #c33;
    padding: 10px 12px;
    margin-bottom: 8px;
  }
  .alarm-box button {
    margin-top: 6px;
    padding: 4px 10px;
    font-size: 12px;
    cursor: pointer;
  }
  .empty { color: #888; font-size: 12px; padding: 8px 0; }
  video { max-width: 320px; display: block; margin-top: 4px; }
</style>
</head>
<body>

<h1>Modellino / Miniparco &mdash; pannello di controllo</h1>
<div class="sub">Aggiornamento automatico ogni 2 secondi</div>

<h2>Allarmi attivi</h2>
<div id="alarms"></div>

<h2>Sensori</h2>
<table>
  <thead><tr><th>Zona</th><th>Tipo</th><th>Lettura</th><th>Buzzer</th><th>Ultimo aggiornamento</th></tr></thead>
  <tbody id="sensors"></tbody>
</table>

<h2>Storico allarmi</h2>
<table>
  <thead><tr><th>Data/ora</th><th>Device</th><th>Tipo</th><th>Stato</th></tr></thead>
  <tbody id="history"></tbody>
</table>

<h2>Video registrati</h2>
<div id="videos"></div>

<script>
function fmtDate(iso) {
  if (!iso) return "-";
  const d = new Date(iso);
  return d.toLocaleString("it-IT");
}

function renderAlarms(alarms) {
  const box = document.getElementById("alarms");
  if (!alarms.length) { box.innerHTML = '<div class="empty">Nessun allarme attivo</div>'; return; }
  box.innerHTML = alarms.map(a => `
    <div class="alarm-box">
      <strong>${a.alarm_type}</strong> &mdash; ${a.device_id}<br>
      Sirena: ${a.sirena_active ? "ON" : "OFF"} | LED polizia: ${a.led_police_active ? "ON" : "OFF"}<br>
      ${fmtDate(a.timestamp)}<br>
      <button onclick="resetAlarm(${a.id})">Riarma / Reset</button>
    </div>
  `).join("");
}

function renderSensors(sensors) {
  const tbody = document.getElementById("sensors");
  tbody.innerHTML = sensors.map(s => `
    <tr>
      <td>${s.zone || "-"}</td>
      <td>${s.type}</td>
      <td>${s.reading ? Object.entries(s.reading).map(([k,v]) => `${k}: ${v ?? "-"}`).join(", ") : "-"}</td>
      <td class="${s.buzzer_active ? "status-warn" : "status-off"}">${s.buzzer_active ? "ATTIVO" : "spento"}</td>
      <td>${fmtDate(s.last_seen)}</td>
    </tr>
  `).join("");
}

async function loadHistory() {
  const res = await fetch("/mini/alarms?limit=30");
  const rows = await res.json();
  document.getElementById("history").innerHTML = rows.map(a => `
    <tr>
      <td>${fmtDate(a.timestamp)}</td>
      <td>${a.device_id}</td>
      <td>${a.alarm_type}</td>
      <td class="${a.resolved ? 'status-ok' : 'status-warn'}">${a.resolved ? "risolto" : "attivo"}</td>
    </tr>
  `).join("") || '<tr><td colspan="4" class="empty">Nessun allarme registrato</td></tr>';
}

async function loadVideos() {
  const res = await fetch("/mini/videos?limit=20");
  const rows = await res.json();
  const box = document.getElementById("videos");
  if (!rows.length) { box.innerHTML = '<div class="empty">Nessun video registrato</div>'; return; }
  box.innerHTML = rows.map(v => `
    <div style="margin-bottom:10px;">
      ${fmtDate(v.timestamp)} &mdash; ${v.device_id} &mdash; trigger: ${v.trigger_event || "-"}<br>
      <video controls src="/${v.video_path}"></video>
    </div>
  `).join("");
}

async function resetAlarm(id) {
  await fetch(`/mini/alarms/${id}/reset`, { method: "POST" });
  loadHistory();
}

const stream = new EventSource("/mini/stream");
stream.onmessage = (ev) => {
  const data = JSON.parse(ev.data);
  renderAlarms(data.active_alarms);
  renderSensors(data.sensors);
};
stream.onerror = () => { /* il browser riprova automaticamente */ };

loadHistory();
loadVideos();
setInterval(loadHistory, 10000);
setInterval(loadVideos, 15000);
</script>

</body>
</html>
"""
