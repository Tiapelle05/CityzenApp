import enum
from datetime import datetime, timezone
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Enum as SQLEnum, Float, Table, Boolean, Index, UniqueConstraint
from sqlalchemy.orm import relationship, backref
from app.db.database import Base

class TypeUser(str, enum.Enum):
    op_eco='op_eco'; admin='admin'; ente='ente'

class TypeDevice(str, enum.Enum):
    camera='camera'; microphone='microphone'; light='light'; basket='basket'; soil_sensor='soil_sensor'
    # Nodi ESP32 del modellino/miniparco fisico
    mini_ambiente='mini_ambiente'; mini_varchi='mini_varchi'; mini_bin='mini_bin'; mini_display='mini_display'
    # Nodo combinato: un solo ESP32 che manda tutti i sensori in un unico payload (differenziato per zona)
    mini_node='mini_node'
    # Server fisico monitorato per consumo (es. presa smart), non un nodo IoT vero e proprio
    server='server'

class TypeEvent(str, enum.Enum):
    alert='alert'; eco='eco'; assistance='assistance'; weight='weight'; humidity='humidity'
    light='light'; motion='motion'; light_on='light_on'; is_dark='is_dark'; full='full'; battery='battery'
    ingresso='ingresso'; uscita='uscita'; power='power'
    # Segnalazione di un cittadino dall'app (nessun device: mac_address nullo, dettaglio in event_citizen)
    citizen='citizen'

class PracticeStatus(str, enum.Enum):
    open='open'; in_progress='in_progress'; resolved='resolved'; closed='closed'

practice_event = Table("practice_event", Base.metadata,
    Column("practice_id", Integer, ForeignKey("practice.id", ondelete="CASCADE"), primary_key=True),
    Column("event_id",    Integer, ForeignKey("event.id",    ondelete="CASCADE"), primary_key=True),
    Column("linked_at",   DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)),
)

class AppUser(Base):
    __tablename__ = "app_user"
    id       = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    password = Column(String, nullable=False)
    type     = Column(SQLEnum(TypeUser, name="type_user"), nullable=False)
    park_id       = Column(Integer, ForeignKey("park.id"), nullable=True)
    totp_secret   = Column(String, nullable=True)
    totp_enabled  = Column(Boolean, nullable=False, default=False)
    last_login    = Column(DateTime(timezone=True), nullable=True)
    failed_logins = Column(Integer, nullable=False, default=0)
    locked_until  = Column(DateTime(timezone=True), nullable=True)

class Device(Base):
    __tablename__ = "device"
    mac_address = Column(String, primary_key=True, index=True)
    zone        = Column(String, nullable=True)
    type        = Column(SQLEnum(TypeDevice, name="type_device"), nullable=False)
    lat         = Column(Float, nullable=True)
    lon         = Column(Float, nullable=True)
    status      = Column(String, nullable=True, default='ok')
    notes       = Column(String, nullable=True)
    last_seen   = Column(DateTime(timezone=True), nullable=True)
    buzzer_active       = Column(Boolean, nullable=False, default=False)
    buzzer_triggered_at = Column(DateTime(timezone=True), nullable=True)
    park_id     = Column(Integer, ForeignKey("park.id"), nullable=True, default=1)
    events      = relationship("Event", back_populates="device", cascade="all, delete")

class Event(Base):
    __tablename__ = "event"
    id                = Column(Integer, primary_key=True, index=True)
    mac_address       = Column(String, ForeignKey("device.mac_address"), nullable=True, index=True)  # nullo per gli eventi 'citizen'
    type              = Column(SQLEnum(TypeEvent, name="type_event"), nullable=False, index=True)
    val_number        = Column(Float, nullable=True)
    sampling_time     = Column(DateTime(timezone=True), nullable=True)
    transmission_time = Column(DateTime(timezone=True), nullable=True, index=True)
    device        = relationship("Device", back_populates="events")
    video         = relationship("EventVideo", back_populates="event", cascade="all, delete", uselist=False, foreign_keys="EventVideo.id_event")
    practices     = relationship("Practice", secondary=practice_event, back_populates="events")

class Practice(Base):
    __tablename__ = "practice"
    __table_args__ = (
        Index("ix_practice_status_category_created", "status", "category", "created_at"),
    )
    id               = Column(Integer, primary_key=True, index=True)
    title            = Column(String, nullable=False)
    status           = Column(SQLEnum(PracticeStatus, name="practice_status"), nullable=False, default=PracticeStatus.open, index=True)
    severity         = Column(Float, nullable=False, default=0.0)
    lat              = Column(Float, nullable=True)
    lon              = Column(Float, nullable=True)
    zone             = Column(String, nullable=True)
    incident_id      = Column(String, nullable=True, index=True)
    created_at       = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at       = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
    resolved_at      = Column(DateTime(timezone=True), nullable=True)
    category         = Column(String, nullable=True, default='security', index=True)
    park_id          = Column(Integer, ForeignKey("park.id"), nullable=True, default=1)
    events = relationship("Event", secondary=practice_event, back_populates="practices")

class PracticeAudit(Base):
    __tablename__ = "practice_audit"
    id          = Column(Integer, primary_key=True, index=True)
    practice_id = Column(Integer, ForeignKey("practice.id", ondelete="CASCADE"), nullable=False)
    actor       = Column(String, nullable=False)
    action      = Column(String, nullable=False)
    detail      = Column(String, nullable=True)
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class MaintenanceLog(Base):
    __tablename__ = "maintenance_log"
    id          = Column(Integer, primary_key=True, index=True)
    mac_address = Column(String, ForeignKey("device.mac_address", ondelete="CASCADE"), nullable=False)
    actor       = Column(String, nullable=False)
    action      = Column(String, nullable=False)
    notes       = Column(String, nullable=True)
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class EventVideo(Base):
    __tablename__ = "event_video"
    id               = Column(Integer, primary_key=True, index=True)
    id_event         = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    video_url        = Column(String, nullable=False)
    thumbnail_url    = Column(String, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    created_at       = Column(DateTime(timezone=True), nullable=False)
    event = relationship("Event", back_populates="video")


class EventAlarm(Base):
    """Storico allarmi del modellino/miniparco: sirena + LED lampeggiante blu 'polizia'.
    Distinta da Practice/EventCamera (usate per gli allarmi 'reali' del parco/telecamera):
    qui teniamo un log semplice e dedicato, con stato riarmabile (resolved)."""
    __tablename__ = "event_alarm"
    id                 = Column(Integer, primary_key=True, index=True)
    device_id          = Column(String, ForeignKey("device.mac_address", ondelete="CASCADE"), nullable=False, index=True)
    alarm_type         = Column(String, nullable=False)   # 'VANDALISMO', 'AFFOLLAMENTO'
    sirena_active      = Column(Boolean, nullable=False, default=False)
    led_police_active  = Column(Boolean, nullable=False, default=False)
    timestamp          = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    resolved           = Column(Boolean, nullable=False, default=False)
    resolved_at        = Column(DateTime(timezone=True), nullable=True)


class TelegramSession(Base):
    """Chat Telegram loggata con /login: chat_id -> utente/ruolo, usata per
    instradare le notifiche (allarmi a modellino/polizia, offline a
    manutenzione) e autorizzare i comandi."""
    __tablename__ = "telegram_session"
    chat_id    = Column(String, primary_key=True)
    user_id    = Column(Integer, ForeignKey("app_user.id", ondelete="CASCADE"), nullable=False)
    role       = Column(String, nullable=False)  # 'police' | 'eco' | 'maintenance' | 'modellino' | 'admin'
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    user       = relationship("AppUser")


class EventPower(Base):
    """Lettura di consumo elettrico (sensore di corrente in linea, es. INA219/
    INA226 su ESP32/Orange Pi, o presa smart per il server)."""
    __tablename__ = "event_power"
    event_id   = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    voltage    = Column(Float, nullable=True)   # Volt
    current_ma = Column(Float, nullable=True)   # milliampere
    power_w    = Column(Float, nullable=True)   # Watt istantanei
    event      = relationship("Event", backref=backref("power_detail", uselist=False), foreign_keys=[event_id])


class Setting(Base):
    """Soglie/parametri configurabili da UI (es. soglia riempimento cestino).
    Chiave/valore semplice, il valore resta stringa e viene castato dal
    chiamante (mqtt.py) al tipo giusto."""
    __tablename__ = "setting"
    key   = Column(String, primary_key=True)
    value = Column(String, nullable=False)


class CommandLog(Base):
    """Storico dei comandi MQTT inviati dal backend verso i device (sirena,
    LED, luci...) — a differenza di Event (dati ricevuti dai device), qui
    teniamo traccia di cosa il backend ha ordinato agli attuatori."""
    __tablename__ = "command_log"
    id         = Column(Integer, primary_key=True, index=True)
    topic      = Column(String, nullable=False)
    payload    = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class MiniVideoLog(Base):
    """Log dei video mock associati a un evento allarme del modellino.
    Nome tabella 'mini_video_log' (diverso da 'event_video', già usato dalla
    pipeline reale delle clip telecamera con schema id_event/video_url)."""
    __tablename__ = "mini_video_log"
    id            = Column(Integer, primary_key=True, index=True)
    device_id     = Column(String, ForeignKey("device.mac_address", ondelete="CASCADE"), nullable=False, index=True)
    video_path    = Column(String, nullable=False)
    trigger_event = Column(String, nullable=True)
    timestamp     = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


# Polymorphic event detail tables

class EventCamera(Base):
    __tablename__ = "event_camera"
    event_id      = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    person_count  = Column(Integer, nullable=True)
    confidence    = Column(Float, nullable=True)
    bbox_json     = Column(String, nullable=True)
    frame_url     = Column(String, nullable=True)
    alert_type    = Column(String, nullable=True)
    temperature_c = Column(Float, nullable=True)
    humidity_pct  = Column(Float, nullable=True)
    event         = relationship("Event", backref=backref("camera_detail", uselist=False), foreign_keys=[event_id])

class EventMicrophone(Base):
    __tablename__ = "event_microphone"
    event_id     = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    decibel      = Column(Float, nullable=True)
    frequency_hz = Column(Float, nullable=True)
    audio_url    = Column(String, nullable=True)
    alert_type   = Column(String, nullable=True)
    noise_db     = Column(Float, nullable=True)
    event        = relationship("Event", backref=backref("mic_detail", uselist=False), foreign_keys=[event_id])

class EventBasket(Base):
    __tablename__ = "event_basket"
    event_id       = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    fill_level_pct = Column(Float, nullable=True)
    weight_kg      = Column(Float, nullable=True)
    battery_pct    = Column(Float, nullable=True)
    last_emptied   = Column(DateTime(timezone=True), nullable=True)
    fill_cm        = Column(Float, nullable=True)
    tilt_angle     = Column(Float, nullable=True)
    event          = relationship("Event", backref=backref("basket_detail", uselist=False), foreign_keys=[event_id])

class EventLight(Base):
    __tablename__ = "event_light"
    event_id   = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    lux_value  = Column(Float, nullable=True)
    lux_ldr    = Column(Float, nullable=True)
    is_on      = Column(Boolean, nullable=True)
    fault_code = Column(String, nullable=True)
    event      = relationship("Event", backref=backref("light_detail", uselist=False), foreign_keys=[event_id])

class EventSoil(Base):
    __tablename__ = "event_soil"
    event_id          = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    humidity_pct      = Column(Float, nullable=True)
    soil_humidity_pct = Column(Float, nullable=True)
    temperature_c     = Column(Float, nullable=True)
    ph                = Column(Float, nullable=True)
    pm25              = Column(Float, nullable=True)
    pm10              = Column(Float, nullable=True)
    noise_db          = Column(Float, nullable=True)
    event             = relationship("Event", backref=backref("soil_detail", uselist=False), foreign_keys=[event_id])


class Park(Base):
    __tablename__ = "park"
    id         = Column(Integer, primary_key=True, index=True)
    name       = Column(String, nullable=False)
    city       = Column(String, nullable=False, default='Legnano')
    address    = Column(String, nullable=True)
    lat        = Column(Float, nullable=True)
    lon        = Column(Float, nullable=True)
    # Raggio (m) dal centro entro cui una segnalazione è "dentro il parco"; nullo = CITIZEN_PARK_RADIUS_M
    radius_m   = Column(Float, nullable=True)
    active     = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class ApiKey(Base):
    __tablename__ = "api_key"
    id         = Column(Integer, primary_key=True, index=True)
    key        = Column(String, nullable=False, unique=True, index=True)
    device_mac = Column(String, ForeignKey("device.mac_address", ondelete="CASCADE"), nullable=True)
    park_id    = Column(Integer, ForeignKey("park.id"), nullable=False)
    label      = Column(String, nullable=False)
    created_by = Column(Integer, ForeignKey("app_user.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_used  = Column(DateTime(timezone=True), nullable=True)
    active     = Column(Boolean, nullable=False, default=True)


class AccessLog(Base):
    __tablename__ = "access_log"
    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("app_user.id"), nullable=True)
    username   = Column(String, nullable=False)
    action     = Column(String, nullable=False)
    ip         = Column(String, nullable=True)
    success    = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


# Citizen App (vedi CITIZEN_API_DESIGN.md)

class Citizen(Base):
    """Installazione anonima dell'app del cittadino. Nessun dato personale:
    dell'install_id generato dall'app si salva solo l'hash."""
    __tablename__ = "citizen"
    id           = Column(Integer, primary_key=True, index=True)
    public_id    = Column(String, nullable=False, unique=True, index=True)  # "c_7Hq2LmX9", va nel token
    install_hash = Column(String(64), nullable=False, unique=True, index=True)  # sha256(install_id)
    platform     = Column(String, nullable=True)
    app_version  = Column(String, nullable=True)
    blocked      = Column(Boolean, nullable=False, default=False)
    created_at   = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    last_seen_at = Column(DateTime(timezone=True), nullable=True)


class CitizenCategory(Base):
    """Categorie delle segnalazioni, lette dall'app con GET /citizen/categories.
    practice_category e merge_types dicono in quale pratica finisce una
    segnalazione e con quali eventi sensore può fondersi."""
    __tablename__ = "citizen_category"
    code              = Column(String, primary_key=True)
    label             = Column(String, nullable=False)
    icon              = Column(String, nullable=True)
    kinds             = Column(String, nullable=False)   # "problem,suggestion"
    practice_category = Column(String, nullable=False)   # security | basket | soil | other
    merge_types       = Column(String, nullable=True)    # "light,is_dark"
    sort_order        = Column(Integer, nullable=False, default=0)
    active            = Column(Boolean, nullable=False, default=True)


class CitizenReport(Base):
    """Problema, suggerimento o feedback inviato da un cittadino. Sopravvive alla
    pratica (che la retention cancella): lo stato visto dal cittadino sta qui."""
    __tablename__ = "citizen_report"
    __table_args__ = (
        UniqueConstraint("citizen_id", "client_ref", name="uq_citizen_report_client_ref"),
        Index("ix_citizen_report_citizen_created", "citizen_id", "created_at"),
    )
    id          = Column(Integer, primary_key=True, index=True)
    citizen_id  = Column(Integer, ForeignKey("citizen.id", ondelete="CASCADE"), nullable=False)
    park_id     = Column(Integer, ForeignKey("park.id"), nullable=False)
    kind        = Column(String, nullable=False)   # problem | suggestion | feedback
    category    = Column(String, ForeignKey("citizen_category.code"), nullable=True)
    title       = Column(String(120), nullable=True)  # titolo delle idee; null per segnalazioni legacy
    visibility  = Column(String(10), nullable=False, default="public", server_default="public")  # public | private
    description = Column(String(1000), nullable=False)
    priority    = Column(String, nullable=True)    # low | medium | high (solo problem)
    lat         = Column(Float, nullable=True)
    lon         = Column(Float, nullable=True)
    rating      = Column(Integer, nullable=True)   # 1..5 (solo feedback)
    photo_path  = Column(String, nullable=True)    # relativo a UPLOAD_DIR
    client_ref  = Column(String(36), nullable=False)
    status      = Column(String, nullable=False, default='received')  # received | in_progress | resolved | closed
    practice_id = Column(Integer, ForeignKey("practice.id", ondelete="SET NULL"), nullable=True, index=True)
    event_id    = Column(Integer, ForeignKey("event.id", ondelete="SET NULL"), nullable=True)
    created_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at  = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))
    history     = relationship("CitizenReportHistory", back_populates="report", cascade="all, delete-orphan",
                               order_by="CitizenReportHistory.at")




class CitizenIdeaVote(Base):
    """Un voto per cittadino e idea pubblica. Le idee sono CitizenReport kind=suggestion."""
    __tablename__ = "citizen_idea_vote"
    __table_args__ = (
        UniqueConstraint("idea_id", "citizen_id", name="uq_citizen_idea_vote"),
        Index("ix_citizen_idea_vote_idea", "idea_id"),
    )
    id         = Column(Integer, primary_key=True, index=True)
    idea_id    = Column(Integer, ForeignKey("citizen_report.id", ondelete="CASCADE"), nullable=False)
    citizen_id = Column(Integer, ForeignKey("citizen.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class CitizenReportHistory(Base):
    __tablename__ = "citizen_report_history"
    id        = Column(Integer, primary_key=True, index=True)
    report_id = Column(Integer, ForeignKey("citizen_report.id", ondelete="CASCADE"), nullable=False, index=True)
    status    = Column(String, nullable=False)
    note      = Column(String, nullable=True)  # visibile al cittadino
    at        = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    report    = relationship("CitizenReport", back_populates="history")


class ParkNotice(Base):
    """Avviso pubblicato dagli operatori e mostrato nell'app del cittadino."""
    __tablename__ = "park_notice"
    id         = Column(Integer, primary_key=True, index=True)
    park_id    = Column(Integer, ForeignKey("park.id"), nullable=False, index=True)
    title      = Column(String(120), nullable=False)
    body       = Column(String(1000), nullable=False)
    level      = Column(String, nullable=False, default='info')  # info | warning | alert
    starts_at  = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    ends_at    = Column(DateTime(timezone=True), nullable=True)
    created_by = Column(Integer, ForeignKey("app_user.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class EventCitizen(Base):
    """Dettaglio dell'evento 'citizen': posizione e categoria vengono dalla
    segnalazione, non da un device."""
    __tablename__ = "event_citizen"
    event_id  = Column(Integer, ForeignKey("event.id", ondelete="CASCADE"), primary_key=True)
    report_id = Column(Integer, ForeignKey("citizen_report.id", ondelete="SET NULL"), nullable=True)
    lat       = Column(Float, nullable=True)
    lon       = Column(Float, nullable=True)
    category  = Column(String, nullable=True)
    priority  = Column(String, nullable=True)
    event     = relationship("Event", backref=backref("citizen_detail", uselist=False), foreign_keys=[event_id])




