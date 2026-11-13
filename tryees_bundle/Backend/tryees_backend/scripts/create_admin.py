import os
import sys
import getpass

# Risale di una cartella (scripts/ -> root del progetto) per poter importare app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.database import SessionLocal, engine
from app.db.models import Base, AppUser
from app.core.security import get_password_hash

def create_user():
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    try:
        print("\n--- REGISTRAZIONE NUOVO UTENTE ---")
        username = input("Inserisci l'username del nuovo utente: ").strip()
        if not username:
            print("Errore: L'username non può essere vuoto.")
            return

        existing_user = db.query(AppUser).filter(AppUser.username == username).first()
        if existing_user:
            print(f"Errore: L'utente '{username}' esiste già.")
            return

        print("\nRuoli utente disponibili:")
        print("1. admin   (Accesso a tutti gli eventi: alert, eco, assistance)")
        print("2. op_eco  (Accesso solo agli eventi: eco)")
        print("3. ente    (Accesso solo agli eventi: alert)")
        choice = input("Seleziona il ruolo (1/2/3) [default: 1]: ").strip()
        
        roles_map = {"1": "admin", "2": "op_eco", "3": "ente"}
        user_type = roles_map.get(choice, "admin")

        password = getpass.getpass(f"Inserisci la password per l'utente '{username}': ")
        confirm_password = getpass.getpass("Conferma la password: ")
        
        if password != confirm_password:
            print("Errore: Le password non coincidono.")
            return
            
        hashed_password = get_password_hash(password)
        
        new_user = AppUser(
            username=username,
            password=hashed_password,
            type=user_type
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        
        print(f"\n--- NUOVO UTENTE REGISTRATO CON SUCCESSO ---")
        print(f"ID Utente : {new_user.id}")
        print(f"Username  : {new_user.username}")
        print(f"Ruolo     : {new_user.type}")
        print(f"\nRiepilogo Accessi Eventi:")
        if user_type == "admin":
            print("- Può vedere TUTTI gli eventi ('alert', 'eco', 'assistance')")
        elif user_type == "op_eco":
            print("- Può vedere SOLO gli eventi 'eco'")
        elif user_type == "ente":
            print("- Può vedere SOLO gli eventi 'alert'")
        print("--------------------------------------------\n")
        
    finally:
        db.close()

if __name__ == "__main__":
    create_user()
