from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

# Directory radice progetto
BASE_DIR = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):

    # GENERALE
    PROJECT_NAME: str = "Treeyes"

    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    DEVICE_OFFLINE_THRESHOLD_MIN: int = 30

    BASE_URL: str

    # POSTGRES
    POSTGRES_USER: str
    POSTGRES_PASSWORD: str
    POSTGRES_DB: str
    POSTGRES_HOST: str
    POSTGRES_PORT: int

    # MQTT
    MQTT_BROKER_HOST: str
    MQTT_BROKER_PORT: int
    MQTT_USERNAME: Optional[str] = None
    MQTT_PASSWORD: Optional[str] = None

    # TELEGRAM (opzionale: se TELEGRAM_BOT_TOKEN e' vuoto il bot resta spento)
    TELEGRAM_BOT_TOKEN: str = ""

    # RETENTION VIDEO: le clip più vecchie di VIDEO_RETENTION_MINUTES vengono
    # eliminate automaticamente (0 = mai). Controllo ogni VIDEO_CLEANUP_INTERVAL_SECONDS.
    VIDEO_RETENTION_MINUTES: int = 60
    VIDEO_CLEANUP_INTERVAL_SECONDS: int = 300
    # RETENTION SEGNALAZIONI: le pratiche aperte da più di PRACTICE_RETENTION_HOURS vengono
    # eliminate insieme ai loro eventi (0 = mai). Stesso intervallo di controllo dei video.
    PRACTICE_RETENTION_HOURS: int = 48
    # Le pratiche SENZA dati di telecamere o microfoni (cestini, suolo, segnalazioni dei
    # cittadini) restano invece PRACTICE_RETENTION_DAYS_NON_SECURITY giorni (0 = mai)
    PRACTICE_RETENTION_DAYS_NON_SECURITY: int = 30
    # Segnalazioni dei cittadini risolte/chiuse da più di N giorni: eliminate con storico e
    # foto (0 = mai). Installazioni senza segnalazioni inattive da N giorni: eliminate (0 = mai)
    CITIZEN_REPORT_RETENTION_DAYS: int = 30
    CITIZEN_INACTIVE_DAYS: int = 365

    # Swagger (/docs, /redoc, /openapi.json). /citizen/openapi.json resta sempre attivo:
    # è il contratto dell'app e contiene solo le API del cittadino
    ENABLE_DOCS: bool = True

    # CITIZEN APP: token dell'installazione anonima e limite di registrazioni per IP
    CITIZEN_TOKEN_EXPIRE_DAYS: int = 30
    CITIZEN_REGISTER_PER_HOUR: int = 20
    # Segnalazioni per cittadino nell'ultima ora, e raggio (m) dal centro del parco
    # usato quando il parco non ha un radius_m suo
    CITIZEN_REPORTS_PER_HOUR: int = 10
    CITIZEN_PARK_RADIUS_M: float = 500.0

    # DATABASE URL
    @property
    def DATABASE_URL(self) -> str:
        return (
            f"postgresql+psycopg2://{self.POSTGRES_USER}:"
            f"{self.POSTGRES_PASSWORD}@"
            f"{self.POSTGRES_HOST}:"
            f"{self.POSTGRES_PORT}/"
            f"{self.POSTGRES_DB}"
        )

    # UPLOADS
    @property
    def UPLOAD_DIR(self) -> str:
        return str(BASE_DIR / "uploads")

    @property
    def VIDEOS_DIR(self) -> str:
        return str(BASE_DIR / "uploads" / "videos")

    # CONFIG
    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        case_sensitive=True,
        extra="ignore"
    )


settings = Settings()