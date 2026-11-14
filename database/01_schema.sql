-- Passa Rápido: estrutura do banco (PostgreSQL 15+ / Supabase)
-- Ordem de execução: 01_schema, 02_funcoes, 03_triggers, 04_seed, 05_supabase (somente no Supabase)

create table tipo_unidade (
    id          smallint generated always as identity primary key,
    nome        text not null unique,
    icone       text not null default 'local_hospital',
    cor_hex     text not null default '#1565C0'
);

create table unidade (
    id               bigint generated always as identity primary key,
    tipo_unidade_id  smallint not null references tipo_unidade (id),
    nome             text not null,
    endereco         text not null,
    bairro           text,
    cidade           text not null,
    uf               char(2) not null,
    latitude         double precision not null check (latitude between -90 and 90),
    longitude        double precision not null check (longitude between -180 and 180),
    telefone         text,
    ativo            boolean not null default true,
    criado_em        timestamptz not null default now()
);
create index idx_unidade_tipo on unidade (tipo_unidade_id) where ativo;
create index idx_unidade_cidade on unidade (cidade, uf);

create table servico (
    id                     smallint generated always as identity primary key,
    nome                   text not null unique,
    descricao              text,
    documentos_necessarios text
);

create table unidade_servico (
    unidade_id  bigint   not null references unidade (id) on delete cascade,
    servico_id  smallint not null references servico (id) on delete cascade,
    primary key (unidade_id, servico_id)
);

create table horario_funcionamento (
    unidade_id  bigint   not null references unidade (id) on delete cascade,
    dia_semana  smallint not null check (dia_semana between 0 and 6), -- 0 = domingo
    abre        time     not null,
    fecha       time     not null,
    primary key (unidade_id, dia_semana)
);

create table usuario (
    id          uuid primary key default gen_random_uuid(), -- no Supabase, igual a auth.users.id
    nome        text not null,
    pontos      integer not null default 0 check (pontos >= 0),
    nivel       text not null default 'iniciante'
                check (nivel in ('iniciante', 'colaborador', 'confiavel')),
    criado_em   timestamptz not null default now()
);

create table registro_fila (
    id               bigint generated always as identity primary key,
    unidade_id       bigint not null references unidade (id) on delete cascade,
    usuario_id       uuid   not null references usuario (id) on delete cascade,
    servico_id       smallint references servico (id),
    tipo             text not null default 'checkin'
                     check (tipo in ('checkin', 'observacao')),
    tamanho_fila     text not null
                     check (tamanho_fila in ('sem_fila', 'curta', 'media', 'longa', 'lotada')),
    status           text not null default 'aguardando'
                     check (status in ('aguardando', 'atendido', 'concluido', 'desistiu', 'expirado')),
    chegada_em       timestamptz not null default now(),
    atendido_em      timestamptz,
    saida_em         timestamptz,
    espera_real_min  integer check (espera_real_min >= 0),
    peso             numeric(3, 1) not null default 1.0,
    check (atendido_em is null or atendido_em >= chegada_em),
    check (saida_em is null or saida_em >= chegada_em)
);
create index idx_registro_unidade_chegada on registro_fila (unidade_id, chegada_em desc);
create index idx_registro_usuario on registro_fila (usuario_id, chegada_em desc);
create index idx_registro_aguardando on registro_fila (chegada_em) where status = 'aguardando';

-- Uma linha por unidade; é a tabela que o app assina em tempo real.
create table situacao_unidade (
    unidade_id          bigint primary key references unidade (id) on delete cascade,
    espera_estimada_min integer,
    nivel               text not null default 'sem_dados'
                        check (nivel in ('sem_dados', 'baixa', 'moderada', 'alta', 'critica')),
    fonte               text not null default 'sem_dados'
                        check (fonte in ('sem_dados', 'tempo_real', 'historico')),
    confianca           smallint not null default 0 check (confianca between 0 and 100),
    pessoas_aguardando  integer not null default 0,
    qtd_registros       integer not null default 0,
    atualizado_em       timestamptz not null default now()
);

create table historico_espera (
    unidade_id        bigint   not null references unidade (id) on delete cascade,
    dia_semana        smallint not null check (dia_semana between 0 and 6),
    hora              smallint not null check (hora between 0 and 23),
    media_espera_min  integer  not null,
    qtd_amostras      integer  not null,
    atualizado_em     timestamptz not null default now(),
    primary key (unidade_id, dia_semana, hora)
);

create table relato (
    id            bigint generated always as identity primary key,
    unidade_id    bigint not null references unidade (id) on delete cascade,
    usuario_id    uuid   not null references usuario (id) on delete cascade,
    tipo          text not null
                  check (tipo in ('sem_medico', 'sem_vacina', 'sem_medicamento', 'sistema_fora',
                                  'sem_senha', 'atendimento_normal', 'outro')),
    descricao     text,
    confirmacoes  integer not null default 0,
    criado_em     timestamptz not null default now(),
    expira_em     timestamptz not null default now() + interval '4 hours'
);
create index idx_relato_unidade_expira on relato (unidade_id, expira_em desc);

create table relato_confirmacao (
    relato_id   bigint not null references relato (id) on delete cascade,
    usuario_id  uuid   not null references usuario (id) on delete cascade,
    criado_em   timestamptz not null default now(),
    primary key (relato_id, usuario_id)
);

create table favorito (
    usuario_id         uuid   not null references usuario (id) on delete cascade,
    unidade_id         bigint not null references unidade (id) on delete cascade,
    limite_espera_min  integer not null default 20 check (limite_espera_min between 0 and 600),
    alerta_ativo       boolean not null default true,
    ultimo_alerta_em   timestamptz,
    criado_em          timestamptz not null default now(),
    primary key (usuario_id, unidade_id)
);

create table notificacao (
    id          bigint generated always as identity primary key,
    usuario_id  uuid   not null references usuario (id) on delete cascade,
    unidade_id  bigint references unidade (id) on delete cascade,
    titulo      text not null,
    mensagem    text not null,
    lida        boolean not null default false,
    criado_em   timestamptz not null default now()
);
create index idx_notificacao_usuario on notificacao (usuario_id, criado_em desc);

create table avaliacao (
    id          bigint generated always as identity primary key,
    unidade_id  bigint not null references unidade (id) on delete cascade,
    usuario_id  uuid   not null references usuario (id) on delete cascade,
    nota        smallint not null check (nota between 1 and 5),
    comentario  text,
    criado_em   timestamptz not null default now(),
    unique (unidade_id, usuario_id)
);

create table movimento_pontos (
    id          bigint generated always as identity primary key,
    usuario_id  uuid not null references usuario (id) on delete cascade,
    pontos      integer not null,
    motivo      text not null
                check (motivo in ('checkin', 'observacao', 'atendimento_confirmado', 'relato',
                                  'relato_confirmado', 'avaliacao')),
    criado_em   timestamptz not null default now()
);
create index idx_movimento_usuario on movimento_pontos (usuario_id, criado_em desc);
