import logging, math, uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from app.db.models import (
    CitizenCategory, CitizenReport, Device, Event, Practice, PracticeStatus, TypeDevice, TypeEvent, practice_event,
)

logger = logging.getLogger(__name__)

# --- Merge in una singola segnalazione (stessa zona) --------------------------
RADIUS_M        = 50.0   # eventi entro questo raggio E nella stessa zona → stessa pratica
WINDOW_MIN      = 15     # finestra temporale per il merge

# --- Segnalazioni dei cittadini (evento 'citizen') ----------------------------
# Una panchina rotta resta rotta: con una segnalazione di mezzo la finestra è di
# 24 ore, in entrambi i sensi (segnalazione → pratica, sensore → pratica con segnalazioni).
CITIZEN_WINDOW_HOURS = 24
# La segnalazione prende la zona del device più vicino del parco entro questo raggio,
# altrimenti non si fonderebbe mai con i sensori (la zona fa parte della chiave del merge)
CITIZEN_ZONE_SNAP_M  = 75.0
CITIZEN_PRIORITY_WEIGHTS = {"low": 2, "medium": 3, "high": 5}
CITIZEN_BONUS        = 0.5   # per segnalazione, fino a CITIZEN_BONUS_MAX
CITIZEN_BONUS_MAX    = 2.0
CITIZEN_SEV_CAP      = 7.0   # una segnalazione non porta mai una pratica oltre questa soglia

# --- Correlazione fra segnalazioni distinte (incident group) ------------------
# Pratiche di zone diverse ma vicine e nello stesso arco temporale vengono
# collegate condividendo lo stesso incident_id: restano azionabili separatamente
# ma l'operatore vede che fanno parte dello stesso incidente.
INCIDENT_RADIUS_M   = 150.0
INCIDENT_WINDOW_MIN = 15

CATEGORY_SECURITY = 'security'
CATEGORY_BASKET   = 'basket'
CATEGORY_SOIL     = 'soil'
CATEGORY_OTHER    = 'other'

SECURITY_TYPES  = {'alert', 'assistance', 'motion', 'light', 'light_on', 'is_dark'}
CRITICAL_TYPES  = {'alert', 'assistance'}
BASKET_TYPES    = {'full', 'battery', 'weight'}
SOIL_TYPES      = {'humidity', 'eco'}

SEVERITY_WEIGHTS = {
    "alert": 9, "assistance": 10, "motion": 6,
    "light": 4, "light_on": 3, "is_dark": 4,
    "full": 3, "battery": 2, "weight": 2,
    "humidity": 2, "eco": 2,
}

EVENT_TITLES = {
    "alert": "Allerta telecamera", "assistance": "Richiesta assistenza",
    "motion": "Movimento rilevato", "light": "Anomalia illuminazione",
    "light_on": "Luce accesa", "is_dark": "Zona buia",
    "full": "Cestino pieno", "battery": "Batteria bassa cestino",
    "weight": "Peso anomalo cestino", "humidity": "Umidità suolo",
}

def _hav(la1, lo1, la2, lo2):
    R = 6_371_000
    p1, p2 = math.radians(la1), math.radians(la2)
    a = math.sin(math.radians(la2-la1)/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(math.radians(lo2-lo1)/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

def _category(ev_type: str) -> str:
    if ev_type in SECURITY_TYPES: return CATEGORY_SECURITY
    if ev_type in BASKET_TYPES:   return CATEGORY_BASKET
    if ev_type in SOIL_TYPES:     return CATEGORY_SOIL
    return CATEGORY_OTHER

def _ev_type(e) -> str:
    return e.type.value if hasattr(e.type, 'value') else str(e.type)

def _sev(events):
    """Severità della pratica. Le segnalazioni dei cittadini non entrano nella media
    dei sensori (la abbasserebbero): aggiungono un bonus che si ferma a CITIZEN_SEV_CAP
    e non tocca mai una pratica già sopra quella soglia."""
    citizen = [e for e in events if _ev_type(e) == 'citizen']
    events  = [e for e in events if _ev_type(e) != 'citizen']
    if not events:
        if not citizen: return 0.0
        base = max(CITIZEN_PRIORITY_WEIGHTS.get(getattr(e.citizen_detail, 'priority', None), 3) for e in citizen)
        return round(min(CITIZEN_SEV_CAP, base + min(CITIZEN_BONUS_MAX, CITIZEN_BONUS * (len(citizen) - 1))), 2)
    weights = [SEVERITY_WEIGHTS.get(_ev_type(e), 1) for e in events]
    avg    = sum(weights) / len(weights)
    bonus  = min(2.0, len(events) * 0.2)
    result = round(min(10.0, avg + bonus), 2)
    if citizen and result < CITIZEN_SEV_CAP:
        result = round(min(CITIZEN_SEV_CAP, result + min(CITIZEN_BONUS_MAX, CITIZEN_BONUS * len(citizen))), 2)
    types  = {_ev_type(e) for e in events}
    if types & CRITICAL_TYPES:
        return max(result, 7.0)
    return result

DANGER_LABELS = {
    "arma": "Arma rilevata", "arma_da_fuoco": "Arma da fuoco rilevata", "coltello": "Coltello rilevato",
    "granata": "Granata rilevata", "esplosione": "Esplosione rilevata", "rissa": "Rissa in corso", "persona_a_terra": "Persona a terra",
    "vandalismo": "Vandalismo in corso", "fuoco_fumo": "Fuoco/fumo rilevato",
    "assembramento": "Assembramento sospetto", "segnale_aiuto": "Segnale di aiuto rilevato",
    "vetro_rotto": "Vetro rotto rilevato", "urla": "Urla rilevate",
    "vandalismo_cestino": "Allarme vandalismo cestino (MPU6050)",
}

def _title(ev_type, device, alert_type=None):
    z = device.zone if device else "zona sconosciuta"
    if alert_type and alert_type in DANGER_LABELS:
        return f"{DANGER_LABELS[alert_type]} – {z}"
    return f"{EVENT_TITLES.get(ev_type, f'Evento {ev_type}')} – {z}"

class CorrelationEngine:

    def process_event(self, event, db):
        ev_type  = _ev_type(event)
        if ev_type in ('ingresso', 'uscita', 'power'):
            # conteggio continuo dei varchi e telemetria consumi elettrici:
            # non generano una pratica di allerta/intervento.
            return None, False
        if ev_type == 'citizen':
            return self._process_citizen(event, db)

        dev      = db.query(Device).filter(Device.mac_address == event.mac_address).first()
        lat      = dev.lat  if dev else None
        lon      = dev.lon  if dev else None
        zone     = dev.zone if dev else None
        now      = datetime.now(timezone.utc)

        category = _category(ev_type)

        practice = self._find(db, lat, lon, now, category, zone, ev_type) if (lat and lon) else None

        if practice:
            db.execute(practice_event.insert().values(practice_id=practice.id, event_id=event.id, linked_at=now))
            db.refresh(practice)
            practice.severity   = _sev(practice.events)
            practice.updated_at = now
            db.commit(); db.refresh(practice)
            logger.info(f"[Correlation] event {event.id} → existing practice {practice.id}")
            return practice, False

        alert_type = None
        if ev_type == 'alert':
            cd = getattr(event, 'camera_detail', None)
            if cd is not None:
                alert_type = cd.alert_type

        # Nessuna pratica compatibile nella stessa zona: ne creiamo una nuova.
        # La colleghiamo però a un incidente esistente se ci sono pratiche vicine
        # aperte nello stesso arco temporale (probabilmente lo stesso evento su
        # più zone), altrimenti apriamo un nuovo incidente.
        incident_id = None
        if lat and lon:
            wsi = now - timedelta(minutes=INCIDENT_WINDOW_MIN)
            incident_id = self._find_incident(db, lat, lon, wsi, category)
        if incident_id is None:
            incident_id = uuid.uuid4().hex

        practice = Practice(
            title       = _title(ev_type, dev, alert_type),
            status      = PracticeStatus.open,
            category    = category,
            severity    = SEVERITY_WEIGHTS.get(ev_type, 1),
            lat=lat, lon=lon,
            zone        = zone,
            incident_id = incident_id,
            created_at  = now, updated_at=now,
        )
        if dev and dev.park_id:
            practice.park_id = dev.park_id
        db.add(practice); db.flush()
        db.execute(practice_event.insert().values(practice_id=practice.id, event_id=event.id, linked_at=now))
        db.commit(); db.refresh(practice)
        logger.info(f"[Correlation] event {event.id} → new practice {practice.id} [{category}] incident={incident_id}")
        return practice, True

    def _process_citizen(self, event, db):
        """Segnalazione di un cittadino: posizione, categoria e parco vengono dalla
        segnalazione (event_citizen), la zona dal device più vicino."""
        cd     = event.citizen_detail
        report = db.get(CitizenReport, cd.report_id) if cd.report_id else None
        cat    = db.get(CitizenCategory, cd.category) if cd.category else None
        category = cat.practice_category if cat else CATEGORY_OTHER
        park_id  = report.park_id if report else None
        lat, lon = cd.lat, cd.lon
        zone     = self._snap_zone(db, park_id, lat, lon)
        now      = datetime.now(timezone.utc)

        practice = self._find(db, lat, lon, now, category, zone, 'citizen', cd.category)
        if practice:
            db.execute(practice_event.insert().values(practice_id=practice.id, event_id=event.id, linked_at=now))
            db.refresh(practice)
            practice.severity   = _sev(practice.events)
            practice.updated_at = now
            db.commit(); db.refresh(practice)
            logger.info(f"[Correlation] citizen event {event.id} → existing practice {practice.id}")
            return practice, False

        incident_id = self._find_incident(db, lat, lon, now - timedelta(minutes=INCIDENT_WINDOW_MIN), category)
        label = cat.label if cat else "Altro"
        practice = Practice(
            title       = f"Segnalazione cittadino: {label} – {zone or 'posizione indicata'}",
            status      = PracticeStatus.open,
            category    = category,
            severity    = _sev([event]),
            lat=lat, lon=lon,
            zone        = zone,
            incident_id = incident_id or uuid.uuid4().hex,
            created_at  = now, updated_at=now,
        )
        if park_id:
            practice.park_id = park_id
        db.add(practice); db.flush()
        db.execute(practice_event.insert().values(practice_id=practice.id, event_id=event.id, linked_at=now))
        db.commit(); db.refresh(practice)
        logger.info(f"[Correlation] citizen event {event.id} → new practice {practice.id} [{category}] zone={zone}")
        return practice, True

    def _snap_zone(self, db, park_id, lat, lon):
        """Zona del device del parco più vicino entro CITIZEN_ZONE_SNAP_M, altrimenti None."""
        q = db.query(Device).filter(Device.zone.isnot(None), Device.lat.isnot(None), Device.lon.isnot(None),
                                    Device.type != TypeDevice.server)
        if park_id:
            q = q.filter(Device.park_id == park_id)
        best, bd = None, float("inf")
        for d in q.all():
            dist = _hav(lat, lon, d.lat, d.lon)
            if dist <= CITIZEN_ZONE_SNAP_M and dist < bd:
                best, bd = d.zone, dist
        return best

    def _find(self, db, lat, lon, now, category, zone, ev_type, citizen_category=None):
        """Cerca una pratica aperta con cui fondere l'evento: stessa categoria,
        stessa zona, dentro la finestra temporale ed entro RADIUS_M metri.
        La zona è parte della chiave: eventi di zone diverse non si fondono mai.
        Se di mezzo c'è una segnalazione di un cittadino la finestra è di
        CITIZEN_WINDOW_HOURS e i tipi di evento devono essere compatibili (_compatible)."""
        base = db.query(Practice).filter(
            Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress]),
            Practice.lat.isnot(None),
            Practice.lon.isnot(None),
            Practice.category == category,
        )
        base = base.filter(Practice.zone == zone) if zone is not None else base.filter(Practice.zone.is_(None))
        citizen_ws = now - timedelta(hours=CITIZEN_WINDOW_HOURS)
        with_citizen = (
            select(practice_event.c.practice_id)
            .join(Event, Event.id == practice_event.c.event_id)
            .where(Event.type == TypeEvent.citizen)
        )
        if ev_type == 'citizen':
            candidates = base.filter(Practice.created_at >= citizen_ws).all()
        else:
            # Il percorso dei sensori resta quello di sempre (15 minuti), più le
            # pratiche con segnalazioni dei cittadini nelle ultime 24 ore
            candidates = base.filter(Practice.created_at >= now - timedelta(minutes=WINDOW_MIN)).all()
            seen = {p.id for p in candidates}
            candidates += [p for p in base.filter(Practice.created_at >= citizen_ws,
                                                  Practice.id.in_(with_citizen)).all() if p.id not in seen]
        citizen_ids = set(db.scalars(
            with_citizen.where(practice_event.c.practice_id.in_([p.id for p in candidates]))
        )) if candidates else set()
        merge_map = self._merge_map(db) if (ev_type == 'citizen' or citizen_ids) else {}

        best, bd = None, float("inf")
        for p in candidates:
            d = _hav(lat, lon, p.lat, p.lon)
            if d > RADIUS_M or d >= bd:
                continue
            if (ev_type == 'citizen' or p.id in citizen_ids) and not self._compatible(p, ev_type, citizen_category, merge_map):
                continue
            best, bd = p, d
        return best

    def _merge_map(self, db):
        """code categoria cittadino → tipi di evento sensore con cui può fondersi."""
        return {c.code: {t.strip() for t in (c.merge_types or "").split(",") if t.strip()}
                for c in db.query(CitizenCategory).all()}

    def _compatible(self, practice, ev_type, citizen_category, merge_map):
        """Evita che una segnalazione finisca in una pratica di natura diversa della
        stessa zona (un lampione spento dentro una rissa) e viceversa."""
        sensor_types, citizen_cats = set(), set()
        for e in practice.events:
            t = _ev_type(e)
            if t == 'citizen':
                citizen_cats.add(getattr(e.citizen_detail, 'category', None))
            else:
                sensor_types.add(t)
        if ev_type == 'citizen':
            return citizen_cats <= {citizen_category} and sensor_types <= merge_map.get(citizen_category, set())
        return all(ev_type in merge_map.get(c, set()) for c in citizen_cats)

    def _find_incident(self, db, lat, lon, ws, category):
        """Restituisce l'incident_id di una pratica aperta vicina (entro
        INCIDENT_RADIUS_M) e recente della stessa categoria, per collegare
        segnalazioni di zone diverse ma probabilmente parte dello stesso evento.
        Restituisce None se non c'è nulla di correlabile."""
        candidates = db.query(Practice).filter(
            Practice.status.in_([PracticeStatus.open, PracticeStatus.in_progress]),
            Practice.created_at >= ws,
            Practice.lat.isnot(None),
            Practice.lon.isnot(None),
            Practice.category == category,
            Practice.incident_id.isnot(None),
        ).all()
        best, bd = None, float("inf")
        for p in candidates:
            d = _hav(lat, lon, p.lat, p.lon)
            if d <= INCIDENT_RADIUS_M and d < bd:
                best, bd = p, d
        return best.incident_id if best else None


def write_audit(db, practice_id, actor, action, detail=None):
    from app.db.models import PracticeAudit
    db.add(PracticeAudit(practice_id=practice_id, actor=actor, action=action, detail=detail))
    db.commit()

correlation_engine = CorrelationEngine()
