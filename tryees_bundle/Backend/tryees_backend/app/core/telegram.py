"""
Bot Telegram Treeyes — login per ruolo + notifiche mirate.

Spento di default: se TELEGRAM_BOT_TOKEN non e' impostato il thread di
polling non parte, tutte le notify_* diventano no-op silenziosi.

LOGIN: /login <username> <password> — stesse credenziali del sito. Il ruolo
si ricava con la stessa logica del frontend (App.jsx: USERNAME_ROLE/TYPE_ROLE)
e viene salvato in TelegramSession assieme al chat_id.

RUOLI E COSA RICEVONO:
  - modellino  -> notifica ogni allarme del modellino (EventAlarm), con
                  bottone inline "Riarma"
  - police     -> notifica gli alert reali da telecamera (Practice categoria
                  security), con tipo/confidenza/zona
  - maintenance-> notifica automatica quando un device smette di rispondere
                  (e quando torna online), controllo periodico in background
  - eco        -> nessuna notifica push; su richiesta, /cestini mostra i
                  cestini pieni in ordine di percorso con link Google Maps
  - admin      -> riceve tutto (utile per test/debug)

COMANDI comuni a tutti i ruoli loggati: /stato, /dispositivi, /logout
"""

import logging
import math
import threading
import time
from datetime import datetime, timezone, timedelta

import requests

from app.core.config import settings

logger = logging.getLogger(__name__)

API_BASE = "https://api.telegram.org"
POLL_TIMEOUT_S = 25
OFFLINE_CHECK_INTERVAL_S = 5 * 60
OFFLINE_THRESHOLD_MIN = settings.DEVICE_OFFLINE_THRESHOLD_MIN

# Stessa logica di risoluzione ruolo di App.jsx (USERNAME_ROLE/TYPE_ROLE)
USERNAME_ROLE = {"polizia": "police", "eco": "eco", "manutenzione": "maintenance", "modellino": "modellino"}
TYPE_ROLE     = {"ente": "police", "op_eco": "eco"}


def _resolve_role(user):
    if user.username in USERNAME_ROLE:
        return USERNAME_ROLE[user.username]
    if user.type.value == "admin":
        return "admin"
    return TYPE_ROLE.get(user.type.value)


def _haversine_m(lat1, lon1, lat2, lon2):
    R = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class TelegramBot:
    def __init__(self):
        self.enabled = bool(settings.TELEGRAM_BOT_TOKEN)
        self._thread = None
        self._offline_thread = None
        self._stop = threading.Event()
        self._offset = 0
        self._notified_offline = set()

    def _url(self, method):
        return f"{API_BASE}/bot{settings.TELEGRAM_BOT_TOKEN}/{method}"

    def _call(self, method, **params):
        try:
            r = requests.post(self._url(method), json=params, timeout=POLL_TIMEOUT_S + 5)
            return r.json()
        except Exception as e:
            logger.error(f"Errore chiamata Telegram {method}: {e}")
            return None

    def _send(self, chat_id, text, keyboard=None):
        kwargs = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
        if keyboard:
            kwargs["reply_markup"] = keyboard
        self._call("sendMessage", **kwargs)

    # ── Sessioni ─────────────────────────────────────────────────────
    def _chat_ids_for_role(self, db, *roles):
        from app.db.models import TelegramSession
        rows = db.query(TelegramSession).filter(TelegramSession.role.in_(roles)).all()
        return [r.chat_id for r in rows]

    def _session(self, db, chat_id):
        from app.db.models import TelegramSession
        return db.query(TelegramSession).filter(TelegramSession.chat_id == str(chat_id)).first()

    # ── Notifiche in uscita ──────────────────────────────────────────
    def notify_alarm(self, alarm, device=None):
        """Allarme modellino (EventAlarm) -> ruoli modellino + admin, con
        bottone inline per riarmarlo."""
        if not self.enabled:
            return
        from app.db.database import SessionLocal
        db = SessionLocal()
        try:
            chat_ids = self._chat_ids_for_role(db, "modellino", "admin")
            if not chat_ids:
                return
            zone = device.zone if device else alarm.device_id
            ts = alarm.timestamp.strftime("%H:%M:%S") if alarm.timestamp else "-"
            text = (
                f"🚨 <b>{alarm.alarm_type}</b>\n"
                f"Zona: {zone}\nDevice: <code>{alarm.device_id}</code>\nOre: {ts}"
            )
            keyboard = {"inline_keyboard": [[{"text": "✅ Riarma", "callback_data": f"reset:{alarm.id}"}]]}
            for chat_id in chat_ids:
                self._send(chat_id, text, keyboard)
        finally:
            db.close()

    def notify_security_alert(self, practice, event, device):
        """Alert reale da telecamera (Practice categoria security) -> ruoli
        police + admin, con tipo/confidenza/zona."""
        if not self.enabled:
            return
        from app.db.database import SessionLocal
        db = SessionLocal()
        try:
            chat_ids = self._chat_ids_for_role(db, "police", "admin")
            if not chat_ids:
                return
            cd = getattr(event, "camera_detail", None)
            alert_type = cd.alert_type if cd and cd.alert_type else "allarme"
            from app.services.correlation import DANGER_LABELS
            alert_type = DANGER_LABELS.get(alert_type, alert_type)
            confidence = f"{cd.confidence*100:.0f}%" if cd and cd.confidence is not None else "-"
            ts = event.transmission_time.strftime("%H:%M:%S") if event.transmission_time else "-"
            text = (
                f"🚨 <b>{alert_type}</b>\n"
                f"Zona: {device.zone if device else event.mac_address}\n"
                f"Confidenza: {confidence}\nOre: {ts}\n"
                f"Pratica: #{practice.id} (severità {practice.severity:.1f})"
            )
            for chat_id in chat_ids:
                self._send(chat_id, text)
        finally:
            db.close()

    def notify_device_status(self, device, online):
        """Device andato offline o tornato online -> ruolo maintenance + admin."""
        if not self.enabled:
            return
        from app.db.database import SessionLocal
        db = SessionLocal()
        try:
            chat_ids = self._chat_ids_for_role(db, "maintenance", "admin")
            if not chat_ids:
                return
            if online:
                text = f"✅ <b>{device.mac_address}</b> è tornato online\nZona: {device.zone or '-'}"
            else:
                text = f"⚠️ <b>{device.mac_address}</b> non risponde più\nZona: {device.zone or '-'}\nTipo: {device.type.value if hasattr(device.type,'value') else device.type}"
            for chat_id in chat_ids:
                self._send(chat_id, text)
        finally:
            db.close()

    def _edit_resolved(self, chat_id, message_id, original_text):
        self._call("editMessageText", chat_id=chat_id, message_id=message_id,
                    text=original_text + "\n\n✅ <i>Riarmato</i>", parse_mode="HTML")

    # ── Comandi in entrata ───────────────────────────────────────────
    def _cmd_login(self, db, chat_id, args):
        from app.db.models import AppUser, TelegramSession
        from app.core.security import verify_password
        if len(args) != 2:
            self._send(chat_id, "Uso: /login username password")
            return
        username, password = args
        user = db.query(AppUser).filter(AppUser.username == username).first()
        if not user or not verify_password(password, user.password):
            self._send(chat_id, "❌ Credenziali errate.")
            return
        role = _resolve_role(user)
        if not role:
            self._send(chat_id, "Il tuo account non ha un ruolo previsto per il bot.")
            return
        row = db.query(TelegramSession).filter(TelegramSession.chat_id == str(chat_id)).first()
        if row:
            row.user_id = user.id
            row.role = role
        else:
            db.add(TelegramSession(chat_id=str(chat_id), user_id=user.id, role=role))
        db.commit()
        role_label = {"police": "Polizia", "eco": "Eco", "maintenance": "Manutenzione", "modellino": "Modellino", "admin": "Admin"}
        self._send(chat_id, f"✅ Loggato come <b>{username}</b> ({role_label.get(role, role)}).")

    def _cmd_logout(self, db, chat_id):
        row = self._session(db, chat_id)
        if row:
            db.delete(row)
            db.commit()
        self._send(chat_id, "Disconnesso.")

    def _cmd_stato(self, db, chat_id):
        from app.db.models import Device, EventAlarm, Practice, PracticeStatus
        threshold = datetime.now(timezone.utc) - timedelta(minutes=OFFLINE_THRESHOLD_MIN)
        total = db.query(Device).count()
        online = db.query(Device).filter(Device.last_seen >= threshold).count()
        active_alarms = db.query(EventAlarm).filter(EventAlarm.resolved == False).count()  # noqa: E712
        open_practices = db.query(Practice).filter(
            Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress])
        ).count()
        self._send(chat_id, (
            f"📊 <b>Stato sistema</b>\n"
            f"Device online: {online}/{total}\n"
            f"Allarmi attivi: {active_alarms}\n"
            f"Pratiche aperte: {open_practices}"
        ))

    def _cmd_dispositivi(self, db, chat_id):
        from app.db.models import Device
        threshold = datetime.now(timezone.utc) - timedelta(minutes=OFFLINE_THRESHOLD_MIN)
        offline = db.query(Device).filter((Device.last_seen < threshold) | Device.last_seen.is_(None)).all()
        if not offline:
            self._send(chat_id, "✅ Tutti i device sono online.")
            return
        lines = [f"• {d.mac_address} ({d.zone or '-'})" for d in offline]
        self._send(chat_id, "⚠️ Device offline:\n" + "\n".join(lines))

    def _cmd_cestini(self, db, chat_id):
        from app.db.models import Device, Event, TypeDevice
        from app.core.mqtt import get_settings, _basket_fill_pct

        bins = db.query(Device).filter(Device.type == TypeDevice.basket).all()
        threshold_pct = get_settings(db)["bin_full_pct"]
        full = []
        for d in bins:
            if d.lat is None or d.lon is None:
                continue
            last_ev = (
                db.query(Event)
                .filter(Event.mac_address == d.mac_address, Event.type.in_(["full", "battery", "weight"]))
                .order_by(Event.transmission_time.desc())
                .first()
            )
            basket = getattr(last_ev, "basket_detail", None) if last_ev else None
            if not basket:
                continue
            fill_pct = basket.fill_level_pct
            if fill_pct is None and basket.fill_cm is not None:
                fill_pct = _basket_fill_pct({"fill_cm": basket.fill_cm})
            if fill_pct is not None and fill_pct >= threshold_pct:
                full.append((d, fill_pct))

        if not full:
            self._send(chat_id, "✅ Nessun cestino pieno al momento.")
            return

        # Percorso: nearest-neighbor a partire dal primo cestino pieno
        route = [full.pop(0)]
        while full:
            last_lat, last_lon = route[-1][0].lat, route[-1][0].lon
            full.sort(key=lambda x: _haversine_m(last_lat, last_lon, x[0].lat, x[0].lon))
            route.append(full.pop(0))

        lines = [f"{i+1}. {d.zone or d.mac_address} — {pct:.0f}% pieno" for i, (d, pct) in enumerate(route)]
        maps_url = "https://www.google.com/maps/dir/?api=1"
        maps_url += f"&origin={route[0][0].lat},{route[0][0].lon}"
        maps_url += f"&destination={route[-1][0].lat},{route[-1][0].lon}"
        if len(route) > 2:
            waypoints = "|".join(f"{d.lat},{d.lon}" for d, _ in route[1:-1])
            maps_url += f"&waypoints={waypoints}"

        self._send(chat_id, f"🗑️ <b>Cestini pieni ({len(route)})</b>\n" + "\n".join(lines) + f"\n\n🗺️ <a href='{maps_url}'>Apri percorso su Google Maps</a>")

    def _handle_command(self, chat_id, text):
        from app.db.database import SessionLocal
        parts = text.split()
        cmd = parts[0].lower()

        if cmd == "/start":
            self._send(chat_id, f"Ciao! Chat id: <code>{chat_id}</code>\n\nAccedi con /login username password.")
            return

        db = SessionLocal()
        try:
            if cmd == "/login":
                self._cmd_login(db, chat_id, parts[1:])
                return

            session = self._session(db, chat_id)
            if not session:
                self._send(chat_id, "Non sei loggato. Usa /login username password.")
                return

            if cmd == "/logout":
                self._cmd_logout(db, chat_id)
            elif cmd == "/stato":
                self._cmd_stato(db, chat_id)
            elif cmd == "/dispositivi":
                self._cmd_dispositivi(db, chat_id)
            elif cmd == "/cestini":
                if session.role not in ("eco", "admin"):
                    self._send(chat_id, "Comando disponibile solo per il ruolo Eco.")
                else:
                    self._cmd_cestini(db, chat_id)
            elif cmd == "/help":
                self._send(chat_id, "/stato — riepilogo\n/dispositivi — device offline\n/cestini — percorso cestini pieni (Eco)\n/logout — esci")
        finally:
            db.close()

    def _handle_callback(self, callback_query):
        from app.db.database import SessionLocal
        from app.db.models import EventAlarm

        chat_id = callback_query["message"]["chat"]["id"]
        message_id = callback_query["message"]["message_id"]
        original_text = callback_query["message"].get("text", "")
        data = callback_query.get("data", "")
        callback_id = callback_query["id"]

        db = SessionLocal()
        try:
            session = self._session(db, chat_id)
            if not session or session.role not in ("modellino", "admin"):
                self._call("answerCallbackQuery", callback_query_id=callback_id, text="Non autorizzato")
                return
            if not data.startswith("reset:"):
                self._call("answerCallbackQuery", callback_query_id=callback_id)
                return
            alarm_id = int(data.split(":")[1])
            alarm = db.query(EventAlarm).filter(EventAlarm.id == alarm_id).first()
            if not alarm:
                self._call("answerCallbackQuery", callback_query_id=callback_id, text="Allarme non trovato")
                return
            if alarm.resolved:
                self._call("answerCallbackQuery", callback_query_id=callback_id, text="Già riarmato")
                return
            from app.core.mqtt import mqtt_manager
            mqtt_manager.reset_alarm(db, alarm)
            self._call("answerCallbackQuery", callback_query_id=callback_id, text="Riarmato ✅")
            self._edit_resolved(chat_id, message_id, original_text)
        finally:
            db.close()

    # ── Loop di polling comandi ──────────────────────────────────────
    def _poll_loop(self):
        logger.info("Telegram bot: polling avviato")
        while not self._stop.is_set():
            resp = self._call("getUpdates", offset=self._offset, timeout=POLL_TIMEOUT_S)
            if not resp or not resp.get("ok"):
                time.sleep(3)
                continue
            for update in resp.get("result", []):
                self._offset = update["update_id"] + 1
                try:
                    if "message" in update and "text" in update["message"]:
                        self._handle_command(update["message"]["chat"]["id"], update["message"]["text"].strip())
                    elif "callback_query" in update:
                        self._handle_callback(update["callback_query"])
                except Exception as e:
                    logger.error(f"Errore gestione update Telegram: {e}")

    # ── Controllo periodico device offline ───────────────────────────
    def _offline_loop(self):
        from app.db.database import SessionLocal
        from app.db.models import Device
        logger.info("Telegram bot: controllo device offline avviato")
        while not self._stop.is_set():
            db = SessionLocal()
            try:
                threshold = datetime.now(timezone.utc) - timedelta(minutes=OFFLINE_THRESHOLD_MIN)
                devices = db.query(Device).all()
                for d in devices:
                    is_offline = d.last_seen is None or d.last_seen < threshold
                    was_notified = d.mac_address in self._notified_offline
                    if is_offline and not was_notified:
                        self._notified_offline.add(d.mac_address)
                        self.notify_device_status(d, online=False)
                    elif not is_offline and was_notified:
                        self._notified_offline.discard(d.mac_address)
                        self.notify_device_status(d, online=True)
            except Exception as e:
                logger.error(f"Errore controllo offline: {e}")
            finally:
                db.close()
            self._stop.wait(OFFLINE_CHECK_INTERVAL_S)

    def start(self):
        if not self.enabled:
            logger.info("Telegram bot disattivato (TELEGRAM_BOT_TOKEN non impostato)")
            return
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()
        self._offline_thread = threading.Thread(target=self._offline_loop, daemon=True)
        self._offline_thread.start()

    def stop(self):
        self._stop.set()


telegram_bot = TelegramBot()
