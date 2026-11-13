import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.database import SessionLocal, engine
from app.db.models import Base
from app.db.init_defaults import seed_default_data


def main():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        print("Inizializzazione dati predefiniti (utenti demo, parco, dispositivi)...")
        seed_default_data(db)
        print("✓ Inizializzazione completata!")
        print("\nUtenti demo pronti con password: 'admin123'")
        print("  - admin")
        print("  - polizia")
        print("  - eco")
        print("  - manutenzione")
        print("  - modellino\n")
    finally:
        db.close()


if __name__ == "__main__":
    main()
