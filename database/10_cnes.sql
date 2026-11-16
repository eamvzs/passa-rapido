-- Passa Rápido: suporte a unidades vindas do CNES (Cadastro Nacional de Estabelecimentos de Saúde, DATASUS).
-- Idempotente: pode ser executado mais de uma vez. Aplique depois de 07_estrutura_dados_reais.sql.

alter table unidade add column if not exists cnes_id bigint;

alter table unidade drop constraint if exists ck_unidade_origem;
alter table unidade add constraint ck_unidade_origem
    check (origem in ('demonstracao', 'openstreetmap', 'cnes'));

create unique index if not exists uq_unidade_cnes_id on unidade (cnes_id) where cnes_id is not null;
