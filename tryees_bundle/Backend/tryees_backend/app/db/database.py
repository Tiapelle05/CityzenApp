import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import settings

logger = logging.getLogger(__name__)

db_url = settings.DATABASE_URL
try:
    engine = create_engine(db_url, pool_pre_ping=True)
    if not db_url.startswith("sqlite"):
        # Verifica immediata se PostgreSQL è raggiungibile
        with engine.connect() as conn:
            pass
except Exception as e:
    logger.warning(f"PostgreSQL non disponibile ({e}). Fallback su database locale SQLite (treeyes.db)")
    db_url = "sqlite:///./treeyes.db"
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
        pool_pre_ping=False
    )
    from sqlalchemy import event
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

