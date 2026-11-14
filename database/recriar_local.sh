#!/usr/bin/env bash
# Recria o banco local de desenvolvimento e carrega todos os scripts.
set -euo pipefail
DB="${1:-passa_rapido}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PSQL="${PSQL:-psql -U postgres}"
$PSQL -q -c "drop database if exists $DB" -c "create database $DB"
for f in 01_schema.sql 02_funcoes.sql 03_triggers.sql 04_seed.sql; do
  $PSQL -q -v ON_ERROR_STOP=1 -d "$DB" -f "$DIR/$f"
done
echo "Banco $DB recriado."
