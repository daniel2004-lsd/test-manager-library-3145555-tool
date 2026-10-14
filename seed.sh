#!/usr/bin/env bash
# T-21 — Sembrador de demostración SOLO por la API (nunca toca SQL).
# Crea: 40 libros, 10 socios, 15 préstamos (3 vencidos vía loaned_at opcional).
# Uso: API_URL=http://localhost:8000 ADMIN_USERNAME=admin ADMIN_PASSWORD=Admin!2026 ./seed.sh
set -euo pipefail

API_URL="${API_URL:-http://localhost:8000}"
BASE="$API_URL/api/v1"
ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-Admin!2026}"

log() { printf '%s\n' "$*"; }

TOKEN=$(curl -sf -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" | jq -r .access_token)
[ -n "$TOKEN" ] && [ "$TOKEN" != null ] || { log "No se pudo iniciar sesión"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')

curlj() { curl -sf "$@" "${AUTH[@]}" -H 'Content-Type: application/json'; }

log "== Sembrando categorías existentes, libros, socios y préstamos contra $BASE =="

CATEGORIAS=$(curlj "$BASE/categories" | jq -c '.items[].id' | tr -d '"')
mapfile -t CATS <<< "$CATEGORIAS"
if [ "${#CATS[@]}" -lt 5 ]; then log "Faltan categorías sembradas por la migración"; exit 1; fi

log "== 40 libros =="
BOOKS=()
for i in $(seq 1 40); do
  cat_id="${CATS[$(( (i - 1) % 5 ))]}"
  isbn=$(printf '97884%08d' "$i")
  id=$(curlj -X POST "$BASE/books" -d "{
    \"title\": \"Título de demostración $i\",
    \"author\": \"Autor $i\",
    \"isbn\": \"$isbn\",
    \"category_id\": \"$cat_id\",
    \"total_copies\": 2
  }" | jq -r .id)
  BOOKS+=("$id")
done
log "   ${#BOOKS[@]} libros creados"

log "== 10 socios =="
MEMBERS=()
for i in $(seq 1 10); do
  id=$(curlj -X POST "$BASE/members" -d "{
    \"full_name\": \"Socio de demostración $i\",
    \"document_number\": \"DEMO-$i\"
  }" | jq -r .id)
  MEMBERS+=("$id")
done
log "   ${#MEMBERS[@]} socios creados"

log "== 15 préstamos (3 vencidos) =="
# Préstamos vencidos: el endpoint acepta loaned_at opcional (extensión documentada);
# vencidos = loaned_at + 14 días anterior a hoy.
OVERDUE_SEEDS=("2026-09-15T10:00:00Z" "2026-09-20T10:00:00Z" "2026-09-25T10:00:00Z")
loans=0
for i in $(seq 0 2); do
  member="${MEMBERS[$i]}"
  book="${BOOKS[$i]}"
  curlj -X POST "$BASE/loans" -d "{
    \"member_id\": \"$member\",
    \"items\": [{\"book_id\": \"$book\"}],
    \"loaned_at\": \"${OVERDUE_SEEDS[$i]}\"
  }" > /dev/null
  loans=$((loans + 1))
done
# 12 préstamos actuales de 1 libro (los socios 3..9 quedan con ≤ 2 activos, límite 3)
for i in $(seq 0 11); do
  member="${MEMBERS[$(( i % 7 + 3 ))]}"
  book="${BOOKS[$(( i + 10 ))]}"
  curlj -X POST "$BASE/loans" -d "{
    \"member_id\": \"$member\",
    \"items\": [{\"book_id\": \"$book\"}]
  }" > /dev/null
  loans=$((loans + 1))
done
log "   $loans préstamos registrados"

VENCIDOS=$(curlj "$BASE/loans/overdue" | jq '.items | length')
log "== Evidencia T-21 =="
log "   /loans/overdue devuelve $VENCIDOS líneas (esperado: 3)"
HOY=$(date -u +%Y-%m-%d)
ROWS=$(curlj "$BASE/reports/most-borrowed?from=2026-09-01&to=$HOY" | jq '.rows | length')
log "   /reports/most-borrowed devuelve $ROWS filas (esperado: > 0)"

[ "$VENCIDOS" = "3" ] || { log "ERROR: se esperaban 3 vencidos"; exit 1; }
[ "$ROWS" -gt 0 ] || { log "ERROR: el reporte quedó vacío"; exit 1; }
log "OK — siembra completa"
