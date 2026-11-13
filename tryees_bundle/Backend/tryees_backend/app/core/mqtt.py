import json, logging, threading, time
from datetime import datetime, timezone, timedelta
import paho.mqtt.client as mqtt
from app.core.config import settings
from app.db.database import SessionLocal
from app.db.models import Device, Event, TypeEvent

logger = logging.getLogger(__name__)

# Soglie di automazione (buzzer/LED) — valori di default, sovrascrivibili da
# UI (tabella "setting") tramite GET/PUT /mini/settings. get_settings() li
# rilegge dal DB con una piccola cache per non interrogarlo ad ogni messaggio.
DEFAULT_SETTINGS = {
    "vandal_tilt_deg":        45.0,   # MPU6050: inclinazione oltre la quale scatta l'allarme
    "bin_full_pct":           80.0,   # riempimento cestino oltre cui la cupola LED passa a rosso
    "crowd_threshold":        10,     # passaggi in zona nell'ultima ora oltre cui scattano segnalazioni affollamento
    "presence_light_seconds": 30,     # durata accensione luce su rilevamento varco/presenza
}
_settings_cache = dict(DEFAULT_SETTINGS)
_settings_cache_ts = 0.0
SETTINGS_CACHE_TTL_S = 20.0

def get_settings(db=None):
    """Soglie correnti (default + eventuali override salvati in DB), con
    cache di pochi secondi per evitare una query ad ogni messaggio MQTT."""
    global _settings_cache, _settings_cache_ts
    now = time.time()
    if now - _settings_cache_ts < SETTINGS_CACHE_TTL_S:
        return _settings_cache
    close_after = db is None
    db = db or SessionLocal()
    try:
        from app.db.models import Setting
        rows = {s.key: s.value for s in db.query(Setting).all()}
        merged = dict(DEFAULT_SETTINGS)
        for k, v in rows.items():
            if k in DEFAULT_SETTINGS:
                merged[k] = type(DEFAULT_SETTINGS[k])(v)
        _settings_cache = merged
        _settings_cache_ts = now
        return merged
    except Exception as e:
        logger.error(f"Errore lettura settings: {e}")
        return _settings_cache
    finally:
        if close_after:
            db.close()

MOCK_VIDEO_PATH = "static/mock_videos/allarme_vandalismo.mp4"

TOPIC_ACTUATOR_ALARM  = "smartcity/actuators/alarm"
TOPIC_ACTUATOR_LIGHTS = "smartcity/actuators/lights"
TOPIC_ACTUATOR_STRIP  = "smartcity/actuators/strip"


# I nodi di zona rimandano la telemetria ambiente a ogni variazione: con un
# sensore polveri rumoroso possono arrivare più letture al secondo. Sotto
# questo intervallo le letture dello stesso device vengono scartate.
ENV_MIN_INTERVAL_S = 5.0

# Durata della sequenza LED nello sketch dei nodi di zona (LED_HOLD_MS): mentre
# è in corso il nodo ignora ogni nuovo comando "ON", quindi una presenza che
# arriva in quel momento va rimandata a sequenza finita.
NODE_LED_HOLD_S = 30.0


def _first(payload, *keys):
    """Primo valore presente tra le chiavi date. A differenza di `a or b`
    non scarta lo 0, che per polveri e umidità del terreno è una lettura valida."""
    for k in keys:
        v = payload.get(k)
        if v is not None:
            return v
    return None


def _basket_fill_pct(payload):
    """Percentuale di riempimento cestino: se il device manda già
    fill_level_pct la usa, altrimenti la deriva da fill_cm/distance_cm
    (sensore a distanza VL53L0X). Stessa logica va usata sia per salvare
    la lettura (_enrich) sia per decidere l'automazione LED (_automations),
    altrimenti un device che manda solo fill_cm non fa mai scattare il LED."""
    fill_pct = payload.get("fill_level_pct")
    if fill_pct is not None:
        return fill_pct
    fill_cm = payload.get("fill_cm") or payload.get("distance_cm")
    if fill_cm is None:
        return None
    return round(max(0, min(100, (1 - float(fill_cm) / 30.0) * 100)), 1)


class MQTTClientManager:
    def __init__(self):
        self.client = mqtt.Client(client_id="fastapi_backend", clean_session=True)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self._last_env_ts = {}   # mac_address -> time.monotonic() dell'ultima lettura ambiente salvata
        self._lights_until = {}  # mac nodo -> time.monotonic() di fine (stimata) della sequenza LED in corso
        self._relight_timers = {}  # mac nodo -> Timer della riaccensione già programmata
        if settings.MQTT_USERNAME and settings.MQTT_PASSWORD:
            self.client.username_pw_set(settings.MQTT_USERNAME, settings.MQTT_PASSWORD)

    def start(self):
        try:
            self.client.connect(settings.MQTT_BROKER_HOST, settings.MQTT_BROKER_PORT, 60)
            self.client.loop_start()
        except Exception as e:
            logger.error(f"MQTT connect error: {e}")

    def stop(self):
        self.client.loop_stop()
        self.client.disconnect()

    def _log_command(self, topic: str, payload: dict):
        db = SessionLocal()
        try:
            from app.db.models import CommandLog
            db.add(CommandLog(topic=topic, payload=json.dumps(payload)))
            db.commit()
        except Exception as e:
            logger.error(f"Errore log comando: {e}")
        finally:
            db.close()

    def publish_command(self, mac_address: str, payload: dict):
        """Pubblica un comando verso un device specifico.
        Il nodo ESP32 dovrà iscriversi a parco/{mac}/cmd."""
        topic = f"parco/{mac_address}/cmd"
        try:
            self.client.publish(topic, json.dumps(payload), qos=1)
            self._log_command(topic, payload)
        except Exception as e:
            logger.error(f"Errore publish comando a {mac_address}: {e}")

    def publish_command_topic(self, topic: str, payload: dict):
        """Pubblica un comando su un topic attuatore condiviso (es. smartcity/actuators/*)."""
        try:
            self.client.publish(topic, json.dumps(payload), qos=1)
            self._log_command(topic, payload)
        except Exception as e:
            logger.error(f"Errore publish su {topic}: {e}")

    def on_connect(self, client, *_):
        logger.info("MQTT connected")
        client.subscribe("parco/#")

    def on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
        except Exception as e:
            logger.warning(f"Payload MQTT non valido | topic={msg.topic} errore={e}")
            return
        try:
            device_id = payload.get("device_id") or payload.get("mac_address")
            if not device_id:
                parts = msg.topic.split("/")
                device_id = parts[1] if len(parts) >= 2 else None
            if not device_id:
                return

            # Gestione esplicita stato offline (es. MQTT LWT o segnalazione di disconnessione)
            status_val = str(payload.get("status") or "").strip().lower()
            online_flag = payload.get("online")
            if status_val == "offline" or online_flag is False:
                db = SessionLocal()
                try:
                    device = db.query(Device).filter(Device.mac_address == device_id).first()
                    if device:
                        if device.status == "ok":
                            device.status = "offline"
                        db.commit()
                        logger.warning(f"Segnalazione stato offline ricevuta per device {device_id}")
                except Exception as e:
                    logger.error(f"Errore gestione stato offline per {device_id}: {e}")
                    db.rollback()
                finally:
                    db.close()
                return

            now = datetime.now(timezone.utc)
            st_str = payload.get("sampling_time")
            if st_str:
                try:
                    st = datetime.fromisoformat(st_str)
                    if st.tzinfo is None: st = st.replace(tzinfo=timezone.utc)
                except Exception:
                    st = now
            else:
                st = now

            db = SessionLocal()
            try:
                device = db.query(Device).filter(Device.mac_address == device_id).first()
                if not device:
                    logger.warning(f"Evento da device non registrato: {device_id} | payload={payload}")
                    return
                device.last_seen = now
                if device.status == "offline":
                    device.status = "ok"
                db.flush()

                msg_type = str(payload.get("type") or "").strip().lower()

                # Presenza vista dalla telecamera (parco/<id>/presence): serve
                # SOLO ad accendere le luci della sua zona. Non è un evento:
                # niente Event/pratica/WebSocket, quindi non compare in webapp.
                dtype = device.type.value if hasattr(device.type, 'value') else str(device.type)
                if dtype == 'camera' and (msg_type == "presence" or msg.topic.endswith("/presence")):
                    db.commit()
                    if payload.get("presence", True):
                        self._activate_lights_for_camera_zone(db, device)
                    return

                is_heartbeat = (
                    msg_type in ("heartbeat", "ping", "keepalive", "status", "alive")
                    or status_val in ("online", "ok")
                    or online_flag is True
                    or msg.topic.endswith(("/heartbeat", "/ping", "/status"))
                )

                events = self._save_events(db, device, payload, st, now, is_heartbeat=is_heartbeat)
                if events:
                    self._correlate(events, db)
            except Exception as e:
                logger.error(f"DB error: {e} | device={device_id} payload={payload}"); db.rollback()
            finally:
                db.close()
        except Exception as e:
            logger.error(f"MQTT error: {e} | topic={msg.topic}")

    def _save_events(self, db, device, payload, st, now, is_heartbeat: bool = False):
        created = []
        raw_type = payload.get("type")
        val      = payload.get("val_number")
        valid_event_types = {t.value for t in TypeEvent}

        # Evento a campo singolo: salva solo se il type è riconosciuto dall'Enum TypeEvent
        if raw_type and str(raw_type).strip().lower() in valid_event_types and val is not None:
            try:
                ev = Event(mac_address=device.mac_address, type=raw_type,
                           val_number=float(val), sampling_time=st, transmission_time=now)
                db.add(ev); db.flush()
                self._enrich(db, ev, device, payload)
                created.append(ev)
            except Exception as e:
                logger.error(f"Event error: {e} | device={device.mac_address} payload={payload}")
            db.commit(); return created

        # Multi-field format: più letture nello stesso payload → un Event per ciascuna
        for key, dtype, is_bool in [
            ("motion",   "motion",   True),
            ("alert",    "alert",    True),
            ("full",     "full",     False),
            ("battery",  "battery",  False),
            ("humidity", "humidity", False),
            ("light",    "light",    False),
            ("ingresso", "ingresso", True),
            ("uscita",   "uscita",   True),
            ("power_w",  "power",    False),
        ]:
            raw = payload.get(key)
            if raw is None or (is_bool and not raw): continue
            if key == "humidity":
                last = self._last_env_ts.get(device.mac_address)
                if last is not None and time.monotonic() - last < ENV_MIN_INTERVAL_S:
                    continue
                self._last_env_ts[device.mac_address] = time.monotonic()
            try:
                vn = 1.0 if is_bool else float(raw)
                ev = Event(mac_address=device.mac_address, type=dtype,
                           val_number=vn, sampling_time=st, transmission_time=now)
                db.add(ev); db.flush()
                self._enrich(db, ev, device, payload)
                created.append(ev)
            except Exception as e:
                logger.error(f"Event {key} error: {e} | device={device.mac_address} payload={payload}")
        db.commit()
        if is_heartbeat and not created:
            logger.debug(f"Heartbeat ricevuto da {device.mac_address}")
        return created

    def _enrich(self, db, ev, device, payload):
        from app.db.models import EventCamera, EventMicrophone, EventBasket, EventLight, EventSoil, EventPower
        ev_type = ev.type.value if hasattr(ev.type, 'value') else str(ev.type)
        dtype   = device.type.value if hasattr(device.type, 'value') else str(device.type)
        try:
            if dtype == 'camera' or ev_type in ('alert', 'motion'):
                db.add(EventCamera(
                    event_id      = ev.id,
                    person_count  = payload.get("person_count"),
                    confidence    = payload.get("confidence"),
                    alert_type    = payload.get("alert_type", ev_type),
                    frame_url     = payload.get("frame_url"),
                    temperature_c = payload.get("temperature_c") or payload.get("temp"),
                    humidity_pct  = payload.get("humidity_pct") or payload.get("humidity"),
                ))
                if dtype == 'camera' and ev_type == 'alert':
                    # Pericolo rilevato dalla telecamera REALE: fa suonare
                    # anche gli altoparlanti del modellino (tutti, essendo
                    # un allarme dell'intero parco, non di un punto singolo).
                    self._broadcast_alarm_to_modellino(db, payload.get("alert_type", "arma"))
                elif dtype == 'camera' and ev_type == 'motion':
                    # Presenza semplice (non un pericolo): accende i LED
                    # gialli della STESSA zona della telecamera, con la
                    # stessa logica (sequenza) del sensore ultrasuoni.
                    self._activate_lights_for_camera_zone(db, device)
            elif dtype == 'microphone' or ev_type == 'assistance':
                db.add(EventMicrophone(
                    event_id     = ev.id,
                    decibel      = payload.get("decibel") or payload.get("noise_db"),
                    frequency_hz = payload.get("frequency_hz"),
                    audio_url    = payload.get("audio_url"),
                    alert_type   = ev_type,
                    noise_db     = payload.get("noise_db") or payload.get("decibel"),
                ))
            elif ev_type in ('full', 'battery', 'weight') or dtype in ('basket', 'mini_bin'):
                fill_cm  = payload.get("fill_cm") or payload.get("distance_cm")
                fill_pct = _basket_fill_pct(payload)
                db.add(EventBasket(
                    event_id       = ev.id,
                    fill_level_pct = fill_pct,
                    weight_kg      = payload.get("weight_kg"),
                    battery_pct    = payload.get("battery_pct"),
                    fill_cm        = fill_cm,
                    tilt_angle     = payload.get("tilt_angle") or payload.get("mpu_angle"),
                ))
            elif dtype == 'light' or ev_type in ('light', 'light_on', 'is_dark'):
                db.add(EventLight(
                    event_id   = ev.id,
                    lux_value  = payload.get("lux_value") or payload.get("lux"),
                    lux_ldr    = payload.get("lux_ldr") or payload.get("ldr"),
                    is_on      = bool(payload.get("is_on", ev_type == 'light_on')),
                    fault_code = payload.get("fault_code"),
                ))
            elif ev_type in ('humidity', 'eco') or dtype == 'soil_sensor':
                # Il nodo di zona non limita la conversione del sensore
                # capacitivo: fuori calibrazione può superare 0-100.
                soil_pct = _first(payload, "soil_humidity_pct", "soil_humidity")
                if soil_pct is not None:
                    soil_pct = max(0.0, min(100.0, float(soil_pct)))
                db.add(EventSoil(
                    event_id          = ev.id,
                    humidity_pct      = _first(payload, "humidity_pct", "humidity"),
                    soil_humidity_pct = soil_pct,
                    temperature_c     = _first(payload, "temperature_c", "temp"),
                    ph                = payload.get("ph"),
                    pm25              = _first(payload, "pm25", "pm2_5"),
                    pm10              = payload.get("pm10"),
                    noise_db          = payload.get("noise_db") or payload.get("decibel"),
                ))

            elif ev_type == 'power':
                db.add(EventPower(
                    event_id   = ev.id,
                    voltage    = payload.get("voltage"),
                    current_ma = payload.get("current_ma"),
                    power_w    = payload.get("power_w"),
                ))
        except Exception as e:
            logger.warning(f"Enrich error: {e} | device={device.mac_address} type={dtype}/{ev_type} payload={payload}")

        self._automations(db, device, ev, ev_type, dtype, payload)

    def _automations(self, db, device, ev, ev_type, dtype, payload):
        """Logiche di automazione: decidono se attivare sirena/LED/luci su un
        device e pubblicano il comando via MQTT sui topic attuatori.
        Guidate dal tipo di evento appena creato (non solo dal tipo device),
        così un payload combinato (più letture nello stesso messaggio) non
        fa scattare lo stesso controllo più volte."""
        try:
            cfg = get_settings(db)
            # Allarme vandalismo cestino (MPU6050) + cestino pieno
            if ev_type in ('full', 'battery', 'weight'):
                tilt = payload.get("tilt_angle") or payload.get("mpu_angle")
                if tilt is not None and float(tilt) >= cfg["vandal_tilt_deg"]:
                    self._raise_security_alert(db, device, "vandalismo_cestino", ev.sampling_time)

                fill_pct = _basket_fill_pct(payload)
                if fill_pct is not None and float(fill_pct) >= cfg["bin_full_pct"]:
                    mqtt_manager.publish_command(device.mac_address, {"led": "red", "reason": "cestino_pieno"})

            # Varchi/ultrasuoni: presenza rilevata → accende le luci + affollamento
            if ev_type in ('ingresso', 'uscita'):
                presence = payload.get("presence")
                if presence is None:
                    presence = ev_type == 'ingresso'
                if presence:
                    self._activate_lights(db, device, cfg["presence_light_seconds"])

                occupancy = self._current_occupancy(db, device.zone)
                if occupancy >= cfg["crowd_threshold"]:
                    from app.db.models import EventAlarm
                    already_active = db.query(EventAlarm).filter(
                        EventAlarm.device_id == device.mac_address,
                        EventAlarm.alarm_type == "AFFOLLAMENTO",
                        EventAlarm.resolved == False,  # noqa: E712
                    ).first()
                    if not already_active:
                        self._raise_alarm(db, device, "AFFOLLAMENTO")
        except Exception as e:
            logger.warning(f"Automation error: {e} | device={device.mac_address} type={dtype}/{ev_type} payload={payload}")

    def _broadcast_alarm_to_modellino(self, db, alert_type):
        """Un pericolo rilevato dalla telecamera reale del parco fa suonare
        gli altoparlanti delle ZONE del modellino (A/B) — non il cestino, che
        resta un allarme locale attivato solo dal proprio sensore d'urto."""
        from app.db.models import EventAlarm, TypeDevice
        modellino_types = (TypeDevice.mini_node, TypeDevice.mini_ambiente,
                            TypeDevice.mini_varchi, TypeDevice.mini_display)
        devices = db.query(Device).filter(Device.type.in_(modellino_types)).all()
        alarms_by_mac = {}
        for d in devices:
            alarm = EventAlarm(device_id=d.mac_address, alarm_type=f"TELECAMERA_{alert_type.upper()}",
                                sirena_active=True, led_police_active=True, resolved=False)
            db.add(alarm)
            alarms_by_mac[d.mac_address] = alarm
            d.buzzer_active = True
            d.buzzer_triggered_at = datetime.now(timezone.utc)
        db.commit()
        for d in devices:
            mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_ALARM, {
                "device_id": d.mac_address, "alarm_id": alarms_by_mac[d.mac_address].id,
                "alarm_type": f"TELECAMERA_{alert_type.upper()}",
                "sirena": True, "led_police": True,
            })
        if devices:
            mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_STRIP, {"state": "lampeggiante"})
            logger.info(f"[Allarme] Telecamera reale ({alert_type}) -> {len(devices)} altoparlanti modellino")
            from app.core.telegram import telegram_bot
            for d in devices:
                telegram_bot.notify_alarm(alarms_by_mac[d.mac_address], d)

    def _raise_alarm(self, db, device, alarm_type):
        """Salva il log in event_alarm, attiva sirena + LED polizia via MQTT,
        e genera un record di log video mock (event_alarm.id incluso nel topic
        così l'attuatore/HMI può correlare il comando all'allarme)."""
        from app.db.models import EventAlarm, MiniVideoLog
        alarm = EventAlarm(device_id=device.mac_address, alarm_type=alarm_type,
                            sirena_active=True, led_police_active=True, resolved=False)
        db.add(alarm); db.flush()
        db.add(MiniVideoLog(device_id=device.mac_address, video_path=MOCK_VIDEO_PATH,
                             trigger_event=alarm_type))
        # tiene anche lo stato "live" sul device stesso (usato dal pannello sintetico)
        device.buzzer_active = True
        device.buzzer_triggered_at = datetime.now(timezone.utc)
        db.commit()
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_ALARM, {
            "device_id": device.mac_address, "alarm_id": alarm.id, "alarm_type": alarm_type,
            "sirena": True, "led_police": True,
        })
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_STRIP, {"state": "lampeggiante"})
        logger.info(f"[Allarme] {alarm_type} su {device.mac_address} (id={alarm.id})")
        from app.core.telegram import telegram_bot
        telegram_bot.notify_alarm(alarm, device)
        return alarm

    def _activate_lights_for_camera_zone(self, db, camera_device):
        """La telecamera non ha luci proprie: trova il nodo (mini_node) della
        STESSA zona e attiva la sua sequenza LED, come se l'avesse rilevata
        il suo ultrasuoni."""
        zone = (camera_device.zone or "").lower()
        needle = "zona a" if "zona a" in zone else ("zona b" if "zona b" in zone else None)
        if not needle:
            return
        zone_device = (
            db.query(Device)
            .filter(Device.type.in_(("mini_node", "mini_varchi", "mini_ambiente")), Device.zone.ilike(f"%{needle}%"))
            .first()
        )
        if not zone_device:
            return
        # La telecamera ripete la presenza finché la persona resta in zona, ma
        # il nodo ignora i comandi mentre la sua sequenza è accesa: senza
        # rimandare, i LED resterebbero spenti fino al messaggio successivo.
        remaining = self._lights_until.get(zone_device.mac_address, 0) - time.monotonic()
        if remaining > 0:
            self._relight_later(zone_device.mac_address, remaining + 0.5)
            return
        self._activate_lights(db, zone_device, get_settings(db)["presence_light_seconds"])

    def _relight_later(self, mac, delay_s):
        timer = self._relight_timers.get(mac)
        if timer is not None and timer.is_alive():
            return
        timer = threading.Timer(delay_s, self._relight, args=(mac,))
        timer.daemon = True
        self._relight_timers[mac] = timer
        timer.start()

    def _relight(self, mac):
        db = SessionLocal()
        try:
            device = db.query(Device).filter(Device.mac_address == mac).first()
            if device:
                self._activate_lights(db, device, get_settings(db)["presence_light_seconds"])
        except Exception as e:
            logger.error(f"Errore riaccensione luci {mac}: {e}")
        finally:
            db.close()

    def _activate_lights(self, db, device, duration_s):
        """Pubblica il comando luci e ne salva il log in event_light (come da spec)."""
        from app.db.models import EventLight
        now = datetime.now(timezone.utc)
        ev = Event(mac_address=device.mac_address, type=TypeEvent.light_on,
                    sampling_time=now, transmission_time=now)
        db.add(ev); db.flush()
        db.add(EventLight(event_id=ev.id, is_on=True, lux_value=None, fault_code=None))
        db.commit()
        if self._lights_until.get(device.mac_address, 0) <= time.monotonic():
            self._lights_until[device.mac_address] = time.monotonic() + NODE_LED_HOLD_S
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_LIGHTS, {
            "device_id": device.mac_address, "status": "ON", "duration_s": duration_s,
        })
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_STRIP, {"state": "fissa"})

    def reset_alarm(self, db, alarm):
        """Riarma un allarme: spegne sirena/LED lato device e lo marca risolto (usato dal pannello)."""
        alarm.resolved = True
        alarm.resolved_at = datetime.now(timezone.utc)
        alarm.sirena_active = False
        alarm.led_police_active = False
        device = db.query(Device).filter(Device.mac_address == alarm.device_id).first()
        if device:
            device.buzzer_active = False
        db.commit()
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_ALARM, {
            "device_id": alarm.device_id, "alarm_id": alarm.id, "sirena": False, "led_police": False,
        })
        mqtt_manager.publish_command_topic(TOPIC_ACTUATOR_STRIP, {"state": "off"})
        return alarm

    def _current_occupancy(self, db, zone):
        """Passaggi dai varchi della zona nell'ultima ora. I nodi di zona hanno
        un solo ultrasuoni all'ingresso: 'uscita' significa soltanto che il
        varco è tornato libero e segue ogni 'ingresso', quindi non va sottratta
        (il conteggio resterebbe sempre a 0/1). Dopo il riarmo di un allarme
        AFFOLLAMENTO della zona il conteggio riparte da zero."""
        from app.db.models import EventAlarm
        z = (zone or "").lower()
        needle = "zona a" if "zona a" in z else ("zona b" if "zona b" in z else None)
        if not needle:
            return 0
        window_start = datetime.now(timezone.utc) - timedelta(hours=1)
        last_reset = (
            db.query(EventAlarm.resolved_at)
            .join(Device, EventAlarm.device_id == Device.mac_address)
            .filter(Device.zone.ilike(f"%{needle}%"), EventAlarm.alarm_type == "AFFOLLAMENTO",
                    EventAlarm.resolved_at.isnot(None))
            .order_by(EventAlarm.resolved_at.desc())
            .first()
        )
        if last_reset:
            reset_at = last_reset[0]
            if reset_at.tzinfo is None:  # SQLite restituisce datetime senza fuso
                reset_at = reset_at.replace(tzinfo=timezone.utc)
            window_start = max(window_start, reset_at)
        return (
            db.query(Event)
            .join(Device, Event.mac_address == Device.mac_address)
            .filter(Device.zone.ilike(f"%{needle}%"), Event.type == TypeEvent.ingresso,
                    Event.transmission_time >= window_start)
            .count()
        )

    def _raise_security_alert(self, db, device, alert_type, sampling_time):
        """Crea un evento 'alert' sintetico così passa dalla stessa pipeline di
        correlazione/notifica usata per gli allarmi telecamera (crea una pratica)."""
        from app.db.models import EventCamera
        now = datetime.now(timezone.utc)
        ev = Event(mac_address=device.mac_address, type=TypeEvent.alert,
                   sampling_time=sampling_time or now, transmission_time=now)
        db.add(ev); db.flush()
        db.add(EventCamera(event_id=ev.id, alert_type=alert_type, confidence=1.0))
        db.commit(); db.refresh(ev)
        self._correlate([ev], db)


    def _correlate(self, events, db):
        from app.services.correlation import correlation_engine
        from app.core.ws_manager import ws_manager
        for event in events:
            try:
                db.refresh(event)
                practice, is_new = correlation_engine.process_event(event, db)
                if practice is None:
                    continue
                status_val = practice.status.value if hasattr(practice.status,'value') else practice.status
                if is_new:
                    msg = {"type": "practice_created", "data": {
                        "id": practice.id, "title": practice.title, "status": status_val,
                        "severity": practice.severity, "lat": practice.lat, "lon": practice.lon,
                        "zone": practice.zone, "category": practice.category,
                        "created_at": str(practice.created_at),
                    }}
                    ev_type_new = event.type.value if hasattr(event.type,'value') else str(event.type)
                    if practice.category == 'security' and ev_type_new == 'alert':
                        from app.core.telegram import telegram_bot
                        telegram_bot.notify_security_alert(practice, event, event.device)
                else:
                    ev_type = event.type.value if hasattr(event.type,'value') else str(event.type)
                    msg = {"type": "practice_updated", "data": {
                        "practice_id": practice.id, "severity": practice.severity,
                        "new_event": {"id": event.id, "type": ev_type,
                                      "val_number": event.val_number, "mac_address": event.mac_address},
                    }}
                ws_manager.broadcast_from_thread(msg)
            except Exception as e:
                logger.error(f"Correlation error event {event.id}: {e}")


mqtt_manager = MQTTClientManager()
