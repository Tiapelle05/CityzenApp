# Tryees – app Flutter collegata al backend

## Avvio del backend

1. Estrarre l'archivio `tryees_backend_integrato.zip`.
2. Aprire un terminale nella cartella `tryees_backend` (quella con `docker-compose.yml`).
3. Eseguire:

   ```bash
   docker compose up -d --build
   ```

4. Verificare `http://localhost:8000/`. La risposta attesa è un JSON con `status: ok`.
5. Dashboard: `http://localhost:5173/`.

Il Compose avvia PostgreSQL, Mosquitto, FastAPI e la dashboard. PostgreSQL viene
inizializzato automaticamente; il backend esegue le migrazioni Alembic all'avvio.
Non serve creare manualmente un database né un file `.env` per il primo avvio locale.

## Avvio Flutter

Questo archivio contiene `pubspec.yaml` nella radice del progetto, come richiesto da
Flutter. Aprire questa cartella in Android Studio oppure entrare qui da terminale.

```bash
flutter pub get
flutter run -d chrome
```

Per un emulatore Android:

```bash
flutter run
```

L'app usa automaticamente `http://10.0.2.2:8000` su Android Emulator e
`http://localhost:8000` su Chrome/desktop.

Per un telefono Android o iPhone fisico collegato alla stessa rete Wi-Fi del PC, sostituire
`192.168.1.10` con l'indirizzo IPv4 del PC (visibile con `ipconfig` su Windows):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

Il firewall del PC deve consentire le connessioni in ingresso sulla porta 8000.

## Funzionalità collegate

- Registrazione anonima dell'installazione e conservazione del token.
- Schermata Inizio: stato reale del parco dal backend.
- Segnala: categoria, priorità, acquisizione GPS, foto facoltativa e invio multipart.
- Idee: invio pubblico/privato, elenco pubblico, ordinamento e voti persistenti.
- Avvisi: elenco e filtri alimentati dagli avvisi attivi del backend.

La selezione automatica usa il primo parco attivo nel database. Il seed iniziale crea
`Parco Robinson` a Legnano. Il backend accetta una segnalazione `problem` solo se il
GPS è entro il raggio configurato del parco (500 metri se non è impostato un raggio
specifico). Per testare l'invio della segnalazione, occorre quindi trovarsi nell'area
del parco configurato.

## URL backend

- API: `http://localhost:8000`
- Health check: `http://localhost:8000/`
- Documentazione API: `http://localhost:8000/docs`

I valori di sicurezza predefiniti del Compose sono adatti solo allo sviluppo locale.
Non esporre il backend su Internet senza sostituire le credenziali e `SECRET_KEY`.
