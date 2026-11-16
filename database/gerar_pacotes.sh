#!/usr/bin/env bash
# Gera os dois arquivos que o usuário cola no SQL Editor do Supabase.
#   supabase_instalar.sql   instalação do zero (banco vazio)
#   supabase_atualizar.sql  atualização de um banco que já recebeu os scripts 01 a 06
set -euo pipefail
cd "$(dirname "$0")"
junta() { local saida="$1"; shift; { echo "-- Passa Rápido: $saida"; echo "-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em Run."; for f in "$@"; do echo; echo "-- ===== $f ====="; cat "$f"; done; } > "$saida"; }
junta supabase_instalar.sql 01_schema.sql 02_funcoes.sql 03_triggers.sql 04_seed.sql 05_supabase.sql 07_estrutura_dados_reais.sql 10_cnes.sql 08_dados_reais_base.sql 09_seguranca_e_regras.sql 13_sugestao_correcao.sql 14_melhorias_publicas.sql
junta supabase_atualizar.sql 07_estrutura_dados_reais.sql 10_cnes.sql 08_dados_reais_base.sql 09_seguranca_e_regras.sql 13_sugestao_correcao.sql 14_melhorias_publicas.sql
wc -c supabase_instalar.sql supabase_atualizar.sql
