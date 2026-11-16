#!/usr/bin/env bash
# Testes de ponta a ponta no navegador (Playwright). Rodam contra o site compilado e usam um Supabase simulado
# (mock.js) para as telas que exigem conta e para o script 14, então não alteram nenhum dado real.
#
# Antes:   cd app && flutter build web --release --no-web-resources-cdn
#          npm install playwright && npx playwright install chromium     (uma vez)
# Rodar:   ./test_e2e/rodar.sh
# Variáveis: HTTPS_PROXY (se a rede exigir proxy para chegar ao mapa e ao Supabase).
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p saida
[ -d ../build/web ] || { echo "Compile o site antes (flutter build web)."; exit 1; }
(cd ../build/web && python3 -m http.server 8090 >/dev/null 2>&1) & P1=$!
node servir.js 8091 >/dev/null 2>&1 & P2=$!
trap 'kill $P1 $P2 2>/dev/null' EXIT
sleep 2
falhas=0
for t in 0*.js; do
  echo "== $t"
  saida=$(node "$t" 2>&1); echo "$saida" | grep -E "^(ok|FALHA)|erros|violações|executou|apareceu|DOM|rota " 
  echo "$saida" | grep -q "^FALHA" && falhas=$((falhas+1))
done
echo
[ "$falhas" -eq 0 ] && echo "TODOS OS ARQUIVOS PASSARAM" || { echo "$falhas arquivo(s) com falha"; exit 1; }
