# Tryees – aggiornamento backend per la sezione Idee

## Cosa è stato aggiunto

Il backend esistente già gestiva registrazione anonima, parchi, stato del parco,
segnalazioni, avvisi e storico. Questa estensione aggiunge il supporto persistente
alla schermata **Idee** senza modificare la grafica Flutter:

- creazione di idee con titolo e descrizione;
- visibilità `public` oppure `private`;
- elenco delle idee pubbliche ordinate per data o numero di voti;
- voto e rimozione del voto;
- un solo voto per cittadino e idea, imposto anche dal database;
- le idee private non sono esposte all'endpoint pubblico;
- le idee riutilizzano `CitizenReport` con `kind=suggestion`, quindi restano visibili
  nella dashboard operatori esistente `/citizen-reports`.

## Nuovi endpoint

Tutti richiedono `Authorization: Bearer <access_token>` ottenuto da
`POST /citizen/register`.

- `GET /citizen/ideas?park_id=1&sort=recent|votes&skip=0&limit=20`
- `POST /citizen/ideas`
- `POST /citizen/ideas/{idea_id}/vote`
- `DELETE /citizen/ideas/{idea_id}/vote`

Payload per creare un'idea:

```json
{
  "park_id": 1,
  "title": "Più ombra vicino all'area giochi",
  "description": "Piantare qualche albero aiuterebbe le famiglie nelle giornate più calde.",
  "visibility": "public",
  "client_ref": "UUID-v4-stabile-per-questo-invio"
}
```

Per un'idea privata impostare `visibility` a `private`.

## Applicazione della modifica

1. Estrarre la cartella `tryees_backend` in una directory di lavoro.
2. Non è necessario predisporre manualmente PostgreSQL o un file `.env` per l'avvio locale: `docker-compose.yml` contiene i valori predefiniti di sviluppo e avvia database, broker MQTT, backend e dashboard.
3. Dalla cartella che contiene `docker-compose.yml`, eseguire:

   ```bash
   docker compose up -d --build
   ```

   Il container backend esegue `alembic upgrade head` prima di avviare Uvicorn.
4. Verificare lo stato con `http://localhost:8000/`.
5. Consultare la documentazione filtrata per l'app cittadino su
   `http://localhost:8000/citizen/openapi.json` oppure Swagger su
   `http://localhost:8000/docs` se abilitato.

## Configurazione locale e sicurezza

I valori predefiniti nel Compose sono esclusivamente per sviluppo locale. Prima di
esporre il servizio su Internet, impostare credenziali PostgreSQL e `SECRET_KEY`
robuste tramite variabili d'ambiente o un file `.env` locale non condiviso.

Il volume Docker `postgres_data` conserva i dati tra gli arresti. Per fermare i
servizi senza cancellare il database usare `docker compose down`; non usare
`docker compose down -v` se si vogliono conservare i dati.
