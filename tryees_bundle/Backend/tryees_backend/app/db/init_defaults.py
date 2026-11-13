import logging
from sqlalchemy.orm import Session
from app.db.models import AppUser, TypeUser, Park, CitizenCategory
from app.core.security import get_password_hash, verify_password

logger = logging.getLogger(__name__)

DEFAULT_USERS = [
    {"username": "admin",        "password": "admin123", "type": TypeUser.admin},
    {"username": "polizia",      "password": "admin123", "type": TypeUser.ente},
    {"username": "eco",          "password": "admin123", "type": TypeUser.op_eco},
    {"username": "manutenzione", "password": "admin123", "type": TypeUser.op_eco},
    {"username": "modellino",    "password": "admin123", "type": TypeUser.admin},
]

# Categorie delle segnalazioni dei cittadini (code, label, icona Material, kinds,
# categoria della pratica, tipi evento sensore con cui può fondersi).
# lighting sta in security perché lì finiscono gli eventi light/is_dark dei lampioni.
DEFAULT_CITIZEN_CATEGORIES = [
    ("lighting",   "Illuminazione",          "lightbulb",         "problem,suggestion", "security", "light,is_dark"),
    ("waste",      "Cestini e rifiuti",      "delete",            "problem",            "basket",   "full,weight,battery"),
    ("green",      "Verde e piante",         "park",              "problem,suggestion", "soil",     "humidity,eco"),
    ("irrigation", "Irrigazione",            "water_drop",        "problem,suggestion", "soil",     "humidity,eco"),
    ("fountains",  "Fontanelle",             "water",             "problem,suggestion", "other",    None),
    ("furniture",  "Arredi e panchine",      "chair",             "problem,suggestion", "other",    None),
    ("cleaning",   "Pulizia",                "cleaning_services", "problem",            "other",    None),
    ("safety",     "Sicurezza",              "shield",            "problem",            "security", None),
    ("play",       "Giochi e area sportiva", "sports_soccer",     "problem,suggestion", "other",    None),
    ("other",      "Altro",                  "more_horiz",        "problem,suggestion", "other",    None),
]


def seed_default_data(db: Session):
    """Assicura che il database contenga il parco e gli utenti demo con password
    corretta, prevenendo errori di login ('credenziali non valide'). I dispositivi
    non vengono creati qui: si registrano dalla dashboard (Admin → Registrazione)."""
    try:
        # 1. Parco predefinito
        park = db.query(Park).filter(Park.id == 1).first()
        if not park:
            park = Park(
                id=1,
                name="Parco Robinson",
                city="Legnano",
                address="Via Don Milani",
                lat=45.6035,
                lon=8.9384,
                active=True,
            )
            db.add(park)
            db.commit()
            logger.info("[Seed] Creato parco predefinito (Parco Robinson)")

        # 2. Utenti demo
        for uinfo in DEFAULT_USERS:
            user = db.query(AppUser).filter(AppUser.username == uinfo["username"]).first()
            if not user:
                hashed = get_password_hash(uinfo["password"])
                new_user = AppUser(
                    username=uinfo["username"],
                    password=hashed,
                    type=uinfo["type"],
                    park_id=1,
                    totp_enabled=False,
                )
                db.add(new_user)
                db.commit()
                logger.info(f"[Seed] Creato utente demo: {uinfo['username']}")
            else:
                # Se la password nel DB non corrisponde a quella demo 'admin123', aggiornala
                if not verify_password(uinfo["password"], user.password):
                    user.password = get_password_hash(uinfo["password"])
                    user.failed_logins = 0
                    user.locked_until = None
                    db.commit()
                    logger.info(f"[Seed] Aggiornata password per utente: {uinfo['username']} -> {uinfo['password']}")

        # 3. Categorie delle segnalazioni dei cittadini: solo quelle mancanti,
        # le modifiche fatte a DB (etichette, active...) non vengono sovrascritte
        existing = {code for (code,) in db.query(CitizenCategory.code)}
        for order, (code, label, icon, kinds, practice_category, merge_types) in enumerate(DEFAULT_CITIZEN_CATEGORIES):
            if code not in existing:
                db.add(CitizenCategory(code=code, label=label, icon=icon, kinds=kinds,
                                       practice_category=practice_category, merge_types=merge_types,
                                       sort_order=order * 10, active=True))
                logger.info(f"[Seed] Creata categoria segnalazioni: {code}")
        db.commit()

    except Exception as e:
        logger.error(f"[Seed] Errore inizializzazione dati predefiniti: {e}")
        db.rollback()
