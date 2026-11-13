#!/usr/bin/env bash
# Applica le migration Alembic al DB già in esecuzione.
# Uso: ./scripts/apply_migrations.sh   (dalla root del progetto)

set -e

DB_CONTAINER="treeyes-db"
BACKEND_CONTAINER="treeyes-backend"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[..]${NC} $1"; }

if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    fail "Container $DB_CONTAINER non in esecuzione. Avvia prima: docker compose up -d db"
fi
ok "Container $DB_CONTAINER attivo"

if ! docker ps --format '{{.Names}}' | grep -q "^${BACKEND_CONTAINER}$"; then
    fail "Container $BACKEND_CONTAINER non in esecuzione. Avvia prima: docker compose --profile prod up -d backend"
fi

info "Applico alembic upgrade head..."
docker exec -i "$BACKEND_CONTAINER" alembic upgrade head
ok "Migrazioni applicate"
