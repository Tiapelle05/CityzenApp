# API Idee della comunità – Tryees

Questa estensione riutilizza `citizen_report` con `kind="suggestion"` per mantenere
compatibilità con la dashboard operatori esistente. Le idee private sono incluse
nell'elenco operatori `/citizen-reports`, ma non compaiono nell'elenco pubblico.

Tutte le rotte richiedono `Authorization: Bearer <access_token>` ottenuto da
`POST /citizen/register`.

## Elencare le idee pubbliche

`GET /citizen/ideas?park_id=1&sort=recent&skip=0&limit=20`

- `sort=recent`: più recenti prima.
- `sort=votes`: più votate prima.
- Le idee private non vengono restituite.
- `voted_by_me` indica se l'installazione autenticata ha già votato.

Risposta:
```json
{
  "items": [
    {
      "id": 12,
      "code": "SEG-2026-000012",
      "title": "Più ombra vicino all'area giochi",
      "description": "Piantare qualche albero aiuterebbe le famiglie.",
      "visibility": "public",
      "vote_count": 24,
      "voted_by_me": false,
      "created_at": "2026-11-10T10:00:00Z"
    }
  ],
  "total": 1
}
```

## Creare un'idea

`POST /citizen/ideas` – JSON

```json
{
  "park_id": 1,
  "title": "Più ombra vicino all'area giochi",
  "description": "Piantare qualche albero aiuterebbe le famiglie nelle giornate più calde.",
  "visibility": "public",
  "client_ref": "a valid UUID v4"
}
```

`visibility` può essere `public` o `private`. L'invio è idempotente per
`(citizen_id, client_ref)`: un reinvio con lo stesso UUID non crea duplicati.
Le idee pubbliche sono visibili alla comunità; quelle private solo agli operatori.

## Votare

`POST /citizen/ideas/{idea_id}/vote`

Aggiunge un voto all'idea pubblica. Il vincolo univoco nel database impedisce
che lo stesso cittadino voti due volte la stessa idea.

## Rimuovere un voto

`DELETE /citizen/ideas/{idea_id}/vote`

Rimuove il voto dell'installazione autenticata. Entrambi gli endpoint restituiscono:

```json
{
  "idea_id": 12,
  "vote_count": 25,
  "voted_by_me": true
}
```

## Note implementative

- Le idee sono registrate come `CitizenReport` di tipo `suggestion`, quindi
  riutilizzano autenticazione, rate limit, storico e flusso operatori esistenti.
- `title` e `visibility` sono nuovi campi nullable/defaulted per non rompere
  le righe `CitizenReport` già presenti.
- La migrazione Alembic `d3a6c9e21f40` dipende dalla migrazione citizen esistente
  `c7e2a9f4d1b3`.
- L'app deve continuare a usare il suo `install_id` stabile e `client_ref` UUID
  stabile per ogni invio.
