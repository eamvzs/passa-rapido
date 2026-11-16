-- Passa Rápido: estrutura para unidades reais (idempotente; pode ser executado mais de uma vez).
-- Origem da unidade: 'demonstracao' (dados de exemplo) ou 'openstreetmap' (cadastro real colaborativo).

alter table unidade add column if not exists origem text not null default 'demonstracao';
alter table unidade add column if not exists osm_id bigint;
alter table unidade add column if not exists horario_padrao boolean not null default true;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'ck_unidade_origem') then
        alter table unidade add constraint ck_unidade_origem check (origem in ('demonstracao', 'openstreetmap'));
    end if;
end;
$$;

create unique index if not exists uq_unidade_osm_id on unidade (osm_id) where osm_id is not null;

-- A view do mapa ganha as duas colunas novas no final (a ordem das anteriores não muda).
create or replace view vw_mapa_unidades as
select u.id, u.nome, u.endereco, u.bairro, u.cidade, u.uf, u.latitude, u.longitude, u.telefone,
       t.id as tipo_unidade_id, t.nome as tipo, t.icone, t.cor_hex,
       s.espera_estimada_min, coalesce(s.nivel, 'sem_dados') as nivel,
       coalesce(s.fonte, 'sem_dados') as fonte, coalesce(s.confianca, 0) as confianca,
       coalesce(s.pessoas_aguardando, 0) as pessoas_aguardando, s.atualizado_em,
       fn_unidade_aberta(u.id) as aberta_agora,
       (select round(avg(a.nota), 1) from avaliacao a where a.unidade_id = u.id) as nota_media,
       (select count(*) from avaliacao a where a.unidade_id = u.id) as qtd_avaliacoes,
       (select count(*) from relato r
         where r.unidade_id = u.id and r.expira_em > now()
           and r.tipo <> 'atendimento_normal') as relatos_ativos,
       u.origem, u.horario_padrao
  from unidade u
  join tipo_unidade t on t.id = u.tipo_unidade_id
  left join situacao_unidade s on s.unidade_id = u.id
 where u.ativo;
