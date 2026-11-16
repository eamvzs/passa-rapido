#!/usr/bin/env bash
# Recria o banco local de desenvolvimento e carrega todos os scripts (sem as partes do Supabase).
set -euo pipefail
DB="${1:-passa_rapido}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PSQL="${PSQL:-psql -U postgres}"
$PSQL -q -c "drop database if exists $DB" -c "create database $DB"
for f in 01_schema.sql 02_funcoes.sql 03_triggers.sql 04_seed.sql 07_estrutura_dados_reais.sql 10_cnes.sql 08_dados_reais_base.sql 09_seguranca_e_regras.sql 13_sugestao_correcao.sql 14_melhorias_publicas.sql; do
  $PSQL -q -v ON_ERROR_STOP=1 -d "$DB" -f "$DIR/$f" 2>&1 | grep -v NOTICE || true
done
echo "Banco $DB recriado."
