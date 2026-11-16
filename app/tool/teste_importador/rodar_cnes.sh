#!/usr/bin/env bash
# Teste de ponta a ponta do importador do CNES, sem internet:
# API do CNES falsa -> importar_cnes.dart -> SQL -> PostgreSQL de teste.
# Uso (a partir da pasta app/):  bash tool/teste_importador/rodar_cnes.sh
set -uo pipefail

APP="$(cd "$(dirname "$0")/../.." && pwd)"
DB_DIR="$(cd "$APP/../database" && pwd)"
DART="${DART:-dart}"
PSQL="${PSQL:-psql -U postgres}"
BANCO=pr_cnes
PORTA=8766
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
subir_servidor() {  # subir_servidor [opções do servidor]
  [ -n "$SERVIDOR_PID" ] && kill "$SERVIDOR_PID" 2>/dev/null && wait "$SERVIDOR_PID" 2>/dev/null
  $DART run tool/teste_importador/servidor_falso_cnes.dart $PORTA "$@" >"$TMP/servidor.log" 2>&1 &
  SERVIDOR_PID=$!
  for i in $(seq 1 60); do curl -s "http://127.0.0.1:$PORTA/ping" >/dev/null 2>&1 && break; sleep 0.5; done
}
URL="http://127.0.0.1:$PORTA/cnes/estabelecimentos"

cd "$APP"

echo "== Banco de teste ($BANCO): scripts 01-04, 07, 10 e 08_dados_reais_base =="
$PSQL -q -c "drop database if exists $BANCO" -c "create database $BANCO" || exit 1
for f in 01_schema.sql 02_funcoes.sql 03_triggers.sql 04_seed.sql 07_estrutura_dados_reais.sql 10_cnes.sql 08_dados_reais_base.sql; do
  $PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$DB_DIR/$f" >/dev/null 2>"$TMP/erro.txt" || { echo "FALHA ao aplicar $f"; cat "$TMP/erro.txt"; exit 1; }
done
$PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$DB_DIR/10_cnes.sql" >/dev/null 2>&1
confere "10_cnes.sql é idempotente (segunda execução sem erro)" "0" "$?"
confere "origem 'cnes' aceita pela restrição" "1" "$(sql "select count(*) from pg_constraint where conname='ck_unidade_origem' and pg_get_constraintdef(oid) like '%cnes%'")"

echo "== Unidades do OpenStreetMap plantadas para testar a troca pelo CNES =="
TIPO_UBS=$(sql "select id from tipo_unidade where nome='UBS'")
TIPO_UPA=$(sql "select id from tipo_unidade where nome='UPA'")
TIPO_INSS=$(sql "select id from tipo_unidade where nome='INSS'")
plantar() {  # tipo nome lat lon osm_id
  sql "insert into unidade (tipo_unidade_id,nome,endereco,cidade,uf,latitude,longitude,origem,osm_id) values ($1,'$2','x','São Paulo','SP',$3,$4,'openstreetmap',$5)" >/dev/null
}
plantar "$TIPO_UBS"  "OSM UBS junto da 3001"      -23.5501 -46.6300 901   # ~11 m do CNES 3001: sai
plantar "$TIPO_UBS"  "OSM UBS longe"              -23.4500 -46.5000 902   # fica
plantar "$TIPO_INSS" "OSM INSS no mesmo lugar"    -23.5500 -46.6300 903   # outro tipo: fica
plantar "$TIPO_UPA"  "OSM UPA junto da 4001"      -23.5894 -46.6351 904   # ~14 m do CNES 4001: sai
plantar "$TIPO_UBS"  "OSM UBS a 400 m"            -23.5536 -46.6300 905   # >150 m: fica

echo "== API do CNES falsa (falha injetada na 1ª requisição, páginas de no máximo 5) =="
subir_servidor --falhar-primeira --max-limite 5

echo "== Importador contra a API falsa =="
$DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --tentativas 3 --saida "$TMP/10.sql" >"$TMP/importador.log" 2>&1
confere "importador terminou sem erro" "0" "$?"
confere "o importador repetiu depois do HTTP 503" "1" "$(grep -c 'HTTP 503' "$TMP/importador.log" | head -1)"
grep -E "^    (UPA|Pronto|UBS)|total importado|tipo fora|outro munic|desabilit|privados|sem nome|sem coord|fora de|repetidos" "$TMP/importador.log"
confere "cabeçalho cita a fonte CNES/DATASUS" "1" "$(head -3 "$TMP/10.sql" | grep -c 'CNES/DATASUS')"
confere "SQL tem menos de 400 KB" "sim" "$([ "$(wc -c < "$TMP/10.sql")" -lt 409600 ] && echo sim || echo não)"
confere "resumo: 26 unidades importadas" "26" "$(grep 'total importado' "$TMP/importador.log" | grep -o '[0-9]*')"

echo "== Aplicação no PostgreSQL =="
$PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$TMP/10.sql" >"$TMP/saida_sql.txt" 2>&1 || { echo "FALHA ao aplicar o SQL gerado"; cat "$TMP/saida_sql.txt"; FALHAS=$((FALHAS + 1)); }

checar() {  # $1 = rótulo
  confere "[$1] total de unidades CNES" "26" "$(sql "select count(*) from unidade where origem='cnes'")"
  for par in "UBS:21" "UPA:2" "Pronto-socorro:3"; do
    tipo="${par%%:*}"; esperado="${par##*:}"
    confere "[$1] $tipo" "$esperado" "$(sql "select count(*) from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.origem='cnes' and t.nome='$tipo'")"
  done
  confere "[$1] cnes_id únicos" "26" "$(sql "select count(distinct cnes_id) from unidade where origem='cnes'")"
  confere "[$1] nome em maiúsculas virou nome próprio, com acento restaurado" "UBS Jardim Icaraí" "$(sql "select nome from unidade where cnes_id=3001")"
  confere "[$1] endereço: rua, número e bairro" "Rua do Icaraí, 123 - Jardim Icaraí" "$(sql "select endereco from unidade where cnes_id=3001")"
  confere "[$1] bairro em nome próprio" "Jardim Icaraí" "$(sql "select bairro from unidade where cnes_id=3001")"
  confere "[$1] apóstrofo e aspas preservados no nome" "UBS Dona Ana D'Avila" "$(sql "select nome from unidade where cnes_id=3002")"
  confere "[$1] apóstrofo e aspas preservados no endereço" "Rua D'Agua do 'Quinze', 45 - Vila D Este" "$(sql "select endereco from unidade where cnes_id=3002")"
  confere "[$1] sigla AMA/UBS e algarismo romano mantidos" "AMA/UBS Integrada Vila Rosa II" "$(sql "select nome from unidade where cnes_id=3012")"
  confere "[$1] número S/N some do endereço" "Avenida Dr Arnaldo - Vila Rosa" "$(sql "select endereco from unidade where cnes_id=3012")"
  confere "[$1] telefone fixo formatado" "(11) 2204-8083" "$(sql "select telefone from unidade where cnes_id=3001")"
  confere "[$1] celular com +55 formatado" "(11) 98765-4321" "$(sql "select telefone from unidade where cnes_id=3012")"
  confere "[$1] telefone já formatado preservado" "(11) 98329-5551" "$(sql "select telefone from unidade where cnes_id=3002")"
  confere "[$1] telefone inválido vira nulo" "" "$(sql "select coalesce(telefone,'') from unidade where cnes_id=3013")"
  confere "[$1] sem rua: texto padrão" "Endereço não informado no CNES" "$(sql "select endereco from unidade where cnes_id=3014")"
  confere "[$1] desabilitada não entra" "0" "$(sql "select count(*) from unidade where cnes_id=3003")"
  confere "[$1] privada sem SUS não entra (UBS e pronto atendimento)" "0" "$(sql "select count(*) from unidade where cnes_id in (3004,4002)")"
  confere "[$1] filantrópica que atende pelo SUS entra" "1" "$(sql "select count(*) from unidade where cnes_id=3005")"
  confere "[$1] sem coordenada, coordenada zero, fora de SP e sem nome não entram" "0" "$(sql "select count(*) from unidade where cnes_id in (3006,3007,3008,3011)")"
  confere "[$1] repetido a 5 m não entra" "0" "$(sql "select count(*) from unidade where cnes_id=3009")"
  confere "[$1] AMA do tipo 73 virou UBS (não UPA)" "UBS|UBS" "$(sql "select string_agg(t.nome,'|' order by u.cnes_id) from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.cnes_id in (4004,4005)")"
  confere "[$1] PA Mun virou Pronto-socorro, com nome por extenso e acento" "Pronto-socorro|Pronto Atendimento Municipal J Macedônia" "$(sql "select t.nome||'|'||u.nome from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.cnes_id=4006")"
  confere "[$1] presídio, centro de detenção e atenção domiciliar não entram" "0" "$(sql "select count(*) from unidade where cnes_id in (3020,3021,3022)")"
  confere "[$1] CS Escola vira Centro de Saúde Escola" "Centro de Saúde Escola Samuel B Pessoa" "$(sql "select nome from unidade where cnes_id=3023")"
  confere "[$1] AMA 24H: nome correto" "AMA 24H José Bonifácio Itaquera" "$(sql "select nome from unidade where cnes_id=4004")"
  confere "[$1] AMA 24H abre 24 horas, os 7 dias" "7|00:00:00|23:59:59" "$(sql "select count(*)||'|'||min(abre)||'|'||max(fecha) from horario_funcionamento where unidade_id=(select id from unidade where cnes_id=4004)")"
  confere "[$1] AMA 12H abre das 7h às 19h, os 7 dias" "7|07:00:00|19:00:00" "$(sql "select count(*)||'|'||min(abre)||'|'||max(fecha) from horario_funcionamento where unidade_id=(select id from unidade where cnes_id=4005)")"
  confere "[$1] histórico estimado da AMA 12H cobre só as 12 horas (84 linhas)" "84" "$(sql "select count(*) from historico_espera where unidade_id=(select id from unidade where cnes_id=4005)")"
  confere "[$1] tipo 73 virou UPA" "UPA" "$(sql "select t.nome from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.cnes_id=4001")"
  confere "[$1] tipos 20 e 21 viraram Pronto-socorro" "2" "$(sql "select count(*) from unidade u join tipo_unidade t on t.id=u.tipo_unidade_id where u.cnes_id in (5001,5101) and t.nome='Pronto-socorro'")"
  confere "[$1] cidade e UF" "São Paulo|SP" "$(sql "select cidade||'|'||uf from unidade where cnes_id=3001")"
  confere "[$1] horário padrão marcado" "26" "$(sql "select count(*) from unidade where origem='cnes' and horario_padrao")"
  confere "[$1] OSM junto de uma unidade do CNES (mesmo tipo) foi desativado" "false|false" "$(sql "select string_agg(ativo::text,'|' order by osm_id) from unidade where osm_id in (901,904)")"
  confere "[$1] OSM longe, de outro tipo ou a mais de 150 m continua ativo" "true|true|true" "$(sql "select string_agg(ativo::text,'|' order by osm_id) from unidade where osm_id in (902,903,905)")"
  confere "[$1] OSM desativado não foi apagado" "5" "$(sql "select count(*) from unidade where origem='openstreetmap'")"
  confere "[$1] demonstração desativada" "0" "$(sql "select count(*) from unidade where origem='demonstracao' and ativo")"
  confere "[$1] horários: UPA CNES 7 dias" "7" "$(sql "select count(*) from horario_funcionamento where unidade_id=(select id from unidade where cnes_id=4001)")"
  confere "[$1] horários: UBS CNES 5 dias" "5" "$(sql "select count(*) from horario_funcionamento where unidade_id=(select id from unidade where cnes_id=3001)")"
  confere "[$1] serviços: UBS CNES 4" "4" "$(sql "select count(*) from unidade_servico where unidade_id=(select id from unidade where cnes_id=3001)")"
  confere "[$1] histórico estimado da UPA CNES: 168 horas" "168" "$(sql "select count(*) from historico_espera where unidade_id=(select id from unidade where cnes_id=4001)")"
  confere "[$1] histórico estimado marcado com 0 amostras" "0" "$(sql "select count(*) from historico_espera h join unidade u on u.id=h.unidade_id where u.origem='cnes' and h.qtd_amostras<>0")"
  confere "[$1] situação vem do histórico" "sim" "$([ "$(sql "select count(*) from situacao_unidade s join unidade u on u.id=s.unidade_id where u.origem='cnes' and u.cnes_id=4001 and s.fonte='historico' and s.espera_estimada_min is not null")" -eq 1 ] && echo sim || echo não)"
  confere "[$1] view do mapa mostra a origem cnes" "26" "$(sql "select count(*) from vw_mapa_unidades where origem='cnes'")"
  confere "[$1] resumo por tipo e origem" "sim" "$([ "$(sql "select sum(ativas) from fn_resumo_dados_reais() where origem='cnes'")" -eq 26 ] && echo sim || echo não)"
  confere "[$1] recomendação devolve unidades do CNES" "sim" "$([ "$(sql "select count(*) from fn_recomendar_unidades(-23.55, -46.63, null::smallint, null::smallint, 15::double precision) r join unidade u on u.id=r.unidade_id where u.origem='cnes'")" -gt 0 ] && echo sim || echo não)"
}
checar "1ª aplicação"

echo "== Idempotência e reativação =="
sql "update unidade set ativo=false, nome='nome velho' where cnes_id=3001" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$TMP/10.sql" >/dev/null 2>&1
confere "reaplicar corrige o nome e reativa a unidade" "UBS Jardim Icaraí|true" "$(sql "select nome||'|'||ativo from unidade where cnes_id=3001")"
checar "2ª aplicação"
confere "nenhuma linha duplicada de histórico" "0" "$(sql "select count(*) from (select unidade_id,dia_semana,hora from historico_espera group by 1,2,3 having count(*)>1) x")"

echo "== Tamanho de página diferente produz o mesmo SQL =="
subir_servidor
$DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --pagina 7 --saida "$TMP/10_b.sql" >"$TMP/b.log" 2>&1
confere "importador com página de 7 terminou sem erro" "0" "$?"
confere "SQL idêntico (exceto a linha da data)" "" "$(diff <(grep -v 'Gerado em' "$TMP/10.sql") <(grep -v 'Gerado em' "$TMP/10_b.sql"))"

echo "== API cujo offset conta PÁGINAS (como a real parece fazer): mesmo SQL, com páginas de 5 e de 20 =="
for lim in 5 1000; do
  subir_servidor --offset-por-pagina --max-limite $lim
  $DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --saida "$TMP/10_p$lim.sql" >"$TMP/p$lim.log" 2>&1
  confere "[máx. $lim por página] importador terminou sem erro" "0" "$?"
  confere "[máx. $lim por página] detectou offset por página (e nunca por registro)" "sim" "$([ "$(grep -c 'offset conta páginas' "$TMP/p$lim.log")" -ge 1 ] && [ "$(grep -c 'offset conta registros' "$TMP/p$lim.log")" -eq 0 ] && echo sim || echo não)"
  confere "[máx. $lim por página] SQL idêntico ao da paginação por registro" "" "$(diff <(grep -v 'Gerado em' "$TMP/10.sql") <(grep -v 'Gerado em' "$TMP/10_p$lim.sql"))"
done
subir_servidor --max-limite 5
$DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --saida "$TMP/10_r.sql" >"$TMP/r.log" 2>&1
confere "paginação por registro detectada como 'registros' (e nunca como páginas)" "sim" "$([ "$(grep -c 'offset conta registros' "$TMP/r.log")" -ge 1 ] && [ "$(grep -c 'offset conta páginas' "$TMP/r.log")" -eq 0 ] && echo sim || echo não)"

echo "== --entrada com o JSON completo (inclui outro município e tipo fora da lista) =="
curl -s "http://127.0.0.1:$PORTA/tudo.json" -o "$TMP/tudo.json"
$DART run tool/importar_cnes.dart --entrada "$TMP/tudo.json" --saida "$TMP/10_c.sql" >"$TMP/c.log" 2>&1
confere "importador com --entrada terminou sem erro" "0" "$?"
confere "SQL idêntico ao da API (exceto a data)" "" "$(diff <(grep -v 'Gerado em' "$TMP/10.sql") <(grep -v 'Gerado em' "$TMP/10_c.sql"))"
confere "descartou o tipo fora da lista" "1" "$(grep 'tipo fora da lista' "$TMP/c.log" | grep -o '[0-9]*$')"
confere "descartou o outro município" "1" "$(grep 'de outro município' "$TMP/c.log" | grep -o '[0-9]*$')"

echo "== Divisão em partes =="
$DART run tool/importar_cnes.dart --entrada "$TMP/tudo.json" --saida "$TMP/parcial.sql" --limite-kb 3 --linhas-por-insert 4 >"$TMP/partes.log" 2>&1
PARTES=$(ls "$TMP"/parcial_parte*.sql 2>/dev/null | wc -l)
confere "SQL dividido em mais de uma parte" "sim" "$([ "$PARTES" -gt 1 ] && echo sim || echo não)"
confere "só a última parte chama prc_completar_unidades_reais" "1" "$(cat "$TMP"/parcial_parte*.sql | grep -c '^call prc_completar_unidades_reais')"
sql "delete from unidade where origem='cnes'" >/dev/null
for p in $(ls "$TMP"/parcial_parte*.sql | sort -V); do $PSQL -q -v ON_ERROR_STOP=1 -d $BANCO -f "$p" >/dev/null 2>&1; done
confere "partes aplicadas em ordem reconstroem as 26 unidades" "26" "$(sql "select count(*) from unidade where origem='cnes'")"

echo "== Travas e erros esperados =="
subir_servidor --ignorar-filtro
$DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --saida "$TMP/d.sql" >"$TMP/d.log" 2>&1
confere "API que ignora o filtro de tipo: para com código 2 e sem SQL" "sim" "$([ $? -eq 2 ] && echo sim || echo não)"
[ -f "$TMP/d.sql" ] && echo "FALHA gerou SQL com o filtro ignorado" && FALHAS=$((FALHAS + 1))
confere "mensagem explica que a API ignorou o filtro" "1" "$(grep -c 'ignorou o filtro' "$TMP/d.log")"
subir_servidor --repetir-pagina
timeout 60 $DART run tool/importar_cnes.dart --url "$URL" --pausa 0 --saida "$TMP/e.sql" >"$TMP/e.log" 2>&1
confere "API que ignora o offset: não entra em loop (terminou, código 0)" "0" "$?"
confere "aviso de página repetida" "sim" "$([ "$(grep -c 'repetiu a mesma' "$TMP/e.log")" -ge 1 ] && echo sim || echo não)"
$DART run tool/importar_cnes.dart --entrada "$TMP/nao_existe.json" >/dev/null 2>&1
confere "arquivo inexistente: código de saída 1" "1" "$?"
echo '{"foo":1}' > "$TMP/ruim.json"
$DART run tool/importar_cnes.dart --entrada "$TMP/ruim.json" --saida "$TMP/x.sql" >/dev/null 2>&1
confere "JSON sem 'estabelecimentos' falha (não gera SQL)" "sim" "$([ $? -ne 0 ] && [ ! -f "$TMP/x.sql" ] && echo sim || echo não)"
$DART run tool/importar_cnes.dart --url "http://127.0.0.1:1/cnes/estabelecimentos" --pausa 0 --tentativas 1 --saida "$TMP/y.sql" >/dev/null 2>&1
confere "API inacessível: código de saída 2 e nenhum SQL" "sim" "$([ $? -eq 2 ] && [ ! -f "$TMP/y.sql" ] && echo sim || echo não)"

echo
if [ "$FALHAS" -eq 0 ]; then echo "TODOS OS TESTES PASSARAM"; else echo "$FALHAS FALHA(S)"; exit 1; fi
