-- Passa Rápido: segunda passada contra duplicatas entre OpenStreetMap e CNES (idempotente).
-- O script do CNES já desativa as unidades do OSM a até 150 m de uma do CNES. Aqui entram as que
-- ficaram mais longe porque as duas bases têm coordenadas diferentes para a MESMA unidade.
--
--   1. Mesmo tipo e nome praticamente igual (similaridade >= 0,9, sem acento e sem maiúsculas), a até 40 km:
--      é a mesma unidade e a coordenada do CNES está errada (há casos a mais de 30 km do lugar certo, e vários
--      no centro da cidade, o endereço padrão de cadastros sem coordenada). Usa-se a coordenada do OpenStreetMap,
--      marcada por quem conhece o lugar.
--   2. Mesmo tipo, CNES a até 800 m e nome parecido (similaridade >= 0,6): é a mesma unidade; o OSM sai.
--
-- Só altera coordenada do CNES no passo 1 e só desativa unidades do OpenStreetMap (nada é apagado).
-- Se o importador do CNES rodar de novo, ele regrava as coordenadas do CNES: rode este script depois.
-- Exige as extensões unaccent e pg_trgm (disponíveis no Supabase).

create extension if not exists unaccent;
create extension if not exists pg_trgm;

with par as (
    select o.latitude as lat, o.longitude as lon, c.id as cid,
           similarity(unaccent(lower(o.nome)), unaccent(lower(c.nome))) as sim,
           6371000 * 2 * asin(sqrt(
                 power(sin(radians(c.latitude - o.latitude) / 2), 2)
               + cos(radians(o.latitude)) * cos(radians(c.latitude))
                 * power(sin(radians(c.longitude - o.longitude) / 2), 2))) as metros
      from unidade o
      join unidade c on c.origem = 'cnes' and c.ativo and c.tipo_unidade_id = o.tipo_unidade_id
                    and abs(c.latitude - o.latitude) < 0.4 and abs(c.longitude - o.longitude) < 0.4
     where o.origem = 'openstreetmap' and o.ativo
), melhor as (
    select distinct on (cid) cid, lat, lon
      from par
     where sim >= 0.9 and metros > 150 and metros <= 40000
     order by cid, sim desc, metros
)
update unidade c
   set latitude = m.lat, longitude = m.lon
  from melhor m
 where c.id = m.cid;

update unidade o
   set ativo = false
 where o.origem = 'openstreetmap'
   and o.ativo
   and exists (
        select 1
          from unidade c
         where c.origem = 'cnes'
           and c.ativo
           and c.tipo_unidade_id = o.tipo_unidade_id
           and abs(c.latitude - o.latitude) < 0.01
           and abs(c.longitude - o.longitude) < 0.01
           and 6371000 * 2 * asin(sqrt(
                 power(sin(radians(c.latitude - o.latitude) / 2), 2)
               + cos(radians(o.latitude)) * cos(radians(c.latitude))
                 * power(sin(radians(c.longitude - o.longitude) / 2), 2))) <= 800
           and similarity(unaccent(lower(o.nome)), unaccent(lower(c.nome))) >= 0.6);

select * from fn_resumo_dados_reais();
