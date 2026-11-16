#!/usr/bin/env bash
# Teste de ponta a ponta do importador de unidades reais, sem internet:
# servidor Overpass falso -> importar_osm.dart -> SQL -> PostgreSQL de teste.
# Uso (a partir da pasta app/):  bash tool/teste_importador/rodar.sh
set -uo pipefail

APP="$(cd "$(dirname "$0")/../.." && pwd)"
DB_DIR="$(cd "$APP/../database" && pwd)"
DART="${DART:-dart}"
PSQL="${PSQL:-psql -U postgres}"
BANCO=pr_real
PORTA=8765
TMP="$(mktemp -d)"
FALHAS=0
SERVIDOR_PID=""

limpar() {
  [ -n "$SERVIDOR_PID" ] && kill "$SERVIDOR_PID" 2>/dev/null
  $PSQL -q -c "drop database if exists $BANCO" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap limpar EXIT

confere() {  # confere "descrição" "esperado" "obtido"
  if [ "$2" == "$3" ]; then echo "ok   $1"; else echo "FALHA $1 (esperado: $2 | obtido: $3)"; FALHAS=$((FALHAS + 1)); fi
}
sql() { $PSQL -At -d $BANCO -c "$1"; }

cd "$APP"

echo "== Banco de teste ($BANCO): scripts 01-04, 07, 10 e 08_dados_reais_base =="
$PSQL -q -c "drop database if exists $BANCO" -c "create database $BANCO" || exit 1
for f in 01_schema.sql 02_funcoes.sql 03_triggers.sql 04_seed.sql 07_estrutura_dados_reais.sql 10_cnes.sql 08_dados_reais_base.sql; do
  $PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$DB_DIR/$f" >/dev/null 2>"$TMP/erro.txt" || { echo "FALHA ao aplicar $f"; cat "$TMP/erro.txt"; exit 1; }
done

echo "== Procedimento sem unidades reais não pode esvaziar o app =="
sql "call prc_completar_unidades_reais()"
confere "unidades de demonstração continuam ativas sem nenhuma real" "23" "$(sql "select count(*) from unidade where origem='demonstracao' and ativo")"

echo "== Servidor Overpass falso (com falha injetada na 1ª requisição) =="
$DART run tool/teste_importador/servidor_falso.dart $PORTA --falhar-primeira >"$TMP/servidor.log" 2>&1 &
SERVIDOR_PID=$!
for i in $(seq 1 40); do curl -s "http://127.0.0.1:$PORTA/ping" >/dev/null 2>&1 && break; sleep 0.5; done

echo "== Importador contra o servidor falso =="
$DART run tool/importar_osm.dart --url "http://127.0.0.1:$PORTA/api/interpreter" --pausa 0 --tentativas 3 --saida "$TMP/08.sql" >"$TMP/importador.log" 2>&1
confere "importador terminou sem erro" "0" "$?"
confere "o importador repetiu depois do HTTP 504" "1" "$(grep -c 'HTTP 504' "$TMP/importador.log" | head -1)"
grep -E "^    (UPA|Pronto|UBS|Poupa|INSS|CRAS)|total importado|sem nome|sem coord|fora do|n.o corresponde|repetidos" "$TMP/importador.log"
head -5 "$TMP/08.sql" | grep -q "ODbL 1.0" && echo "ok   cabeçalho com atribuição ODbL" || { echo "FALHA cabeçalho sem atribuição"; FALHAS=$((FALHAS + 1)); }
confere "SQL tem menos de 400 KB" "sim" "$([ "$(wc -c < "$TMP/08.sql")" -lt 409600 ] && echo sim || echo não)"

echo "== Aplicação no PostgreSQL =="
$PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$TMP/08.sql" >"$TMP/saida_sql.txt" 2>&1 || { echo "FALHA ao aplicar o SQL gerado"; cat "$TMP/saida_sql.txt"; FALHAS=$((FALHAS + 1)); }

checar_estado() {  # $1 = rótulo da rodada
  confere "[$1] total de unidades reais" "18" "$(sql "select count(*) from unidade where origem='openstreetmap'")"
  for par in "UPA:4" "Pronto-socorro:2" "UBS:5" "Poupatempo:3" "INSS:2" "CRAS:2"; do
    tipo="${par%%:*}"; esperado="${par##*:}"
    confere "[$1] $tipo" "$esperado" "$(sql "select count(*) from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.origem='openstreetmap' and t.nome='$tipo'")"
  done
  confere "[$1] osm_id únicos" "18" "$(sql "select count(distinct osm_id) from unidade where origem='openstreetmap'")"
  confere "[$1] way 5001 e node 5001 convivem (ids distintos)" "2" "$(sql "select count(*) from unidade where osm_id in (5001, 1000000000005001)")"
  confere "[$1] id de way = id + 1e15" "1" "$(sql "select count(*) from unidade where osm_id=1000000000002001 and nome='UPA Santo Amaro'")"
  confere "[$1] nome com aspas e acentos preservado" "1" "$(sql "select count(*) from unidade where osm_id=1002 and nome=\$\$upa são josé d'Água\$\$")"
  confere "[$1] endereço com aspas, barra invertida e aspas duplas" "1" "$(sql "select count(*) from unidade where osm_id=1002 and endereco like \$\$Rua do 'Quinze' \"Novembro\" \\\\ Teste, 15\$\$")"
  confere "[$1] endereço completo (rua, número e bairro)" "Rua Domingos de Morais, 2564 - Vila Mariana" "$(sql "select endereco from unidade where osm_id=1001")"
  confere "[$1] sem rua: texto padrão" "Endereço não informado no OpenStreetMap" "$(sql "select endereco from unidade where osm_id=1000000000002001")"
  confere "[$1] primeiro telefone de uma lista" "+55 11 3333-0001" "$(sql "select telefone from unidade where osm_id=1001")"
  confere "[$1] telefone de contact:phone" "1133330003" "$(sql "select telefone from unidade where osm_id=1002")"
  confere "[$1] duplicado próximo do Poupatempo Sé foi descartado" "0" "$(sql "select count(*) from unidade where osm_id=2000000000007001")"
  confere "[$1] duplicado próximo da UPA Vila Mariana (3 m) descartado" "0" "$(sql "select count(*) from unidade where osm_id=1005")"
  confere "[$1] UPAMENTO, CREAS, Amara e hospital privado não entram" "0" "$(sql "select count(*) from unidade where osm_id in (1006,7003,4005,3003)")"
  confere "[$1] UPA Pronto-Socorro Mooca classificada como UPA" "UPA" "$(sql "select t.nome from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.osm_id=3004")"
  confere "[$1] hospital público com emergência virou Pronto-socorro" "Pronto-socorro" "$(sql "select t.nome from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.osm_id=3002")"
  confere "[$1] origem e horário padrão" "18" "$(sql "select count(*) from unidade where origem='openstreetmap' and horario_padrao and cidade='São Paulo' and uf='SP'")"
  confere "[$1] demonstração desativada" "0" "$(sql "select count(*) from unidade where origem='demonstracao' and ativo")"
  confere "[$1] demonstração preservada (inativa)" "23" "$(sql "select count(*) from unidade where origem='demonstracao' and not ativo")"
  confere "[$1] horários: UPA 7 dias" "7" "$(sql "select count(*) from horario_funcionamento where unidade_id=(select id from unidade where osm_id=1001)")"
  confere "[$1] horários: UBS 5 dias" "5" "$(sql "select count(*) from horario_funcionamento where unidade_id=(select id from unidade where osm_id=4001)")"
  confere "[$1] horários: Poupatempo 6 dias (seg-sex + sábado)" "6" "$(sql "select count(*) from horario_funcionamento where unidade_id=(select id from unidade where osm_id=5001)")"
  confere "[$1] serviços: UPA 4" "4" "$(sql "select count(*) from unidade_servico where unidade_id=(select id from unidade where osm_id=1001)")"
  confere "[$1] serviços: CRAS 2" "2" "$(sql "select count(*) from unidade_servico where unidade_id=(select id from unidade where osm_id=7001)")"
  confere "[$1] histórico estimado da UPA: 7 dias x 24 h" "168" "$(sql "select count(*) from historico_espera where unidade_id=(select id from unidade where osm_id=1001)")"
  confere "[$1] histórico do UBS: 5 dias x 9 h (8h às 17h)" "45" "$(sql "select count(*) from historico_espera where unidade_id=(select id from unidade where osm_id=4001)")"
  confere "[$1] histórico estimado marcado com 0 amostras (exceto a linha real plantada)" "$2" "$(sql "select count(*) from historico_espera h join unidade u on u.id=h.unidade_id where u.origem='openstreetmap' and h.qtd_amostras<>0")"
  confere "[$1] histórico sem valores negativos" "0" "$(sql "select count(*) from historico_espera where media_espera_min<0")"
  confere "[$1] situação das UPAs vem do histórico" "4" "$(sql "select count(*) from situacao_unidade s join unidade u on u.id=s.unidade_id join tipo_unidade t on t.id=u.tipo_unidade_id where u.origem='openstreetmap' and t.nome='UPA' and s.fonte='historico' and s.espera_estimada_min is not null")"
  confere "[$1] recomendação só devolve unidades reais" "0" "$(sql "select count(*) from fn_recomendar_unidades(-23.5505, -46.6333, null::smallint, null::smallint, 15::double precision) r join unidade u on u.id=r.unidade_id where u.origem<>'openstreetmap'")"
  confere "[$1] recomendação devolve alguma unidade" "sim" "$([ "$(sql "select count(*) from fn_recomendar_unidades(-23.5505, -46.6333, null::smallint, null::smallint, 15::double precision)")" -gt 0 ] && echo sim || echo não)"
  confere "[$1] resumo por tipo e origem" "18" "$(sql "select sum(ativas) from fn_resumo_dados_reais()")"
}

checar_estado "1ª aplicação" 0

echo "== Dado real não pode ser sobrescrito pelo modelo =="
UNI=$(sql "select id from unidade where osm_id=1001")
sql "update historico_espera set media_espera_min=77, qtd_amostras=9 where unidade_id=$UNI and dia_semana=1 and hora=10" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$TMP/08.sql" >/dev/null 2>&1
confere "linha com dado de cidadãos permanece (77 min, 9 amostras)" "77|9" "$(sql "select media_espera_min||'|'||qtd_amostras from historico_espera where unidade_id=$UNI and dia_semana=1 and hora=10")"

echo "== Idempotência: segunda aplicação do mesmo SQL =="
checar_estado "2ª aplicação" 1
confere "nenhuma linha duplicada de histórico" "0" "$(sql "select count(*) from (select unidade_id,dia_semana,hora from historico_espera group by 1,2,3 having count(*)>1) x")"

echo "== Consolidação real sobrescreve o modelo =="
sql "insert into usuario (id, nome) values ('11111111-1111-4111-8111-111111111111','Teste') on conflict do nothing" >/dev/null
sql "alter table registro_fila disable trigger user" >/dev/null
sql "insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, status, chegada_em, atendido_em, espera_real_min) select $UNI,'11111111-1111-4111-8111-111111111111','checkin','media','concluido', (date_trunc('day', now() at time zone 'America/Sao_Paulo') - interval '1 day' + interval '9 hours') at time zone 'America/Sao_Paulo', now(), 33" >/dev/null
sql "alter table registro_fila enable trigger user" >/dev/null
sql "call prc_consolidar_historico(60)" >/dev/null
confere "consolidação gravou amostra real (qtd_amostras >= 1)" "1" "$(sql "select count(*) from historico_espera where unidade_id=$UNI and qtd_amostras>=1 and media_espera_min=33")"

echo "== --entrada com o JSON completo gera o mesmo SQL =="
curl -s "http://127.0.0.1:$PORTA/tudo.json" -o "$TMP/tudo.json"
$DART run tool/importar_osm.dart --entrada "$TMP/tudo.json" --saida "$TMP/08_entrada.sql" >"$TMP/entrada.log" 2>&1
confere "importador com --entrada terminou sem erro" "0" "$?"
confere "SQL idêntico (exceto a linha da data de geração)" "" "$(diff <(grep -v 'Gerado em' "$TMP/08.sql") <(grep -v 'Gerado em' "$TMP/08_entrada.sql"))"

echo "== Divisão em partes quando passa do limite =="
$DART run tool/importar_osm.dart --entrada "$TMP/tudo.json" --saida "$TMP/parcial.sql" --limite-kb 3 --linhas-por-insert 5 >"$TMP/partes.log" 2>&1
PARTES=$(ls "$TMP"/parcial_parte*.sql 2>/dev/null | wc -l)
confere "SQL dividido em mais de uma parte" "sim" "$([ "$PARTES" -gt 1 ] && echo sim || echo não)"
confere "só a última parte chama prc_completar_unidades_reais" "1" "$(cat "$TMP"/parcial_parte*.sql | grep -c '^call prc_completar_unidades_reais')"
$PSQL -q -d $BANCO -c "delete from unidade where origem='openstreetmap'" >/dev/null 2>&1
for p in $(ls "$TMP"/parcial_parte*.sql | sort -V); do $PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$p" >/dev/null 2>&1; done
confere "partes aplicadas em ordem reconstroem as 18 unidades" "18" "$(sql "select count(*) from unidade where origem='openstreetmap'")"

echo "== Erros esperados =="
$DART run tool/importar_osm.dart --entrada "$TMP/nao_existe.json" >/dev/null 2>&1
confere "arquivo inexistente: código de saída 1" "1" "$?"
echo '{"foo":1}' > "$TMP/ruim.json"
$DART run tool/importar_osm.dart --entrada "$TMP/ruim.json" --saida "$TMP/x.sql" >/dev/null 2>&1
confere "JSON sem 'elements' falha (não gera SQL)" "sim" "$([ $? -ne 0 ] && [ ! -f "$TMP/x.sql" ] && echo sim || echo não)"
$DART run tool/importar_osm.dart --url "http://127.0.0.1:1/api/interpreter" --pausa 0 --tentativas 1 --saida "$TMP/y.sql" >/dev/null 2>&1
confere "servidor inacessível: código de saída 2 e nenhum SQL" "sim" "$([ $? -eq 2 ] && [ ! -f "$TMP/y.sql" ] && echo sim || echo não)"

echo
if [ "$FALHAS" -eq 0 ]; then echo "TODOS OS TESTES PASSARAM"; else echo "$FALHAS FALHA(S)"; exit 1; fi
