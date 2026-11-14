-- Passa Rápido: instalação completa no Supabase.
-- Cole este arquivo inteiro no SQL Editor e clique em Run. Gerado a partir dos scripts 01 a 05.

-- ===== 01_schema.sql =====
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

-- ===== 02_funcoes.sql =====
-- Passa Rápido: funções, procedures e views (PL/pgSQL)

-- Distância em km entre dois pontos (fórmula de Haversine).
create or replace function fn_distancia_km(
    p_lat1 double precision, p_lng1 double precision,
    p_lat2 double precision, p_lng2 double precision
) returns double precision
language plpgsql immutable as $$
declare
    v_dlat double precision := radians(p_lat2 - p_lat1);
    v_dlng double precision := radians(p_lng2 - p_lng1);
    v_a    double precision;
begin
    v_a := sin(v_dlat / 2) ^ 2
         + cos(radians(p_lat1)) * cos(radians(p_lat2)) * sin(v_dlng / 2) ^ 2;
    return 6371 * 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
end;
$$;

-- Converte a percepção do usuário em minutos estimados.
create or replace function fn_minutos_por_tamanho(p_tamanho text) returns integer
language plpgsql immutable as $$
begin
    return case p_tamanho
        when 'sem_fila' then 0
        when 'curta'    then 15
        when 'media'    then 40
        when 'longa'    then 80
        when 'lotada'   then 150
        else null
    end;
end;
$$;

create or replace function fn_nivel_por_minutos(p_minutos integer) returns text
language plpgsql immutable as $$
begin
    if p_minutos is null then return 'sem_dados'; end if;
    if p_minutos <= 15 then return 'baixa'; end if;
    if p_minutos <= 45 then return 'moderada'; end if;
    if p_minutos <= 90 then return 'alta'; end if;
    return 'critica';
end;
$$;

create or replace function fn_nivel_por_pontos(p_pontos integer) returns text
language plpgsql immutable as $$
begin
    if p_pontos >= 200 then return 'confiavel'; end if;
    if p_pontos >= 50 then return 'colaborador'; end if;
    return 'iniciante';
end;
$$;

-- Peso do registro no cálculo: usuários com mais reputação influenciam mais.
create or replace function fn_peso_usuario(p_usuario_id uuid) returns numeric
language plpgsql stable as $$
declare
    v_nivel text;
begin
    select nivel into v_nivel from usuario where id = p_usuario_id;
    return case v_nivel
        when 'confiavel'   then 2.0
        when 'colaborador' then 1.5
        else 1.0
    end;
end;
$$;

create or replace function fn_dia_semana_local(p_momento timestamptz) returns smallint
language sql immutable as $$
    select extract(dow from p_momento at time zone 'America/Sao_Paulo')::smallint;
$$;

create or replace function fn_hora_local(p_momento timestamptz) returns smallint
language sql immutable as $$
    select extract(hour from p_momento at time zone 'America/Sao_Paulo')::smallint;
$$;

-- Indica se a unidade está aberta no momento informado.
create or replace function fn_unidade_aberta(p_unidade_id bigint, p_momento timestamptz default now())
returns boolean
language plpgsql stable as $$
declare
    v_hora time := (p_momento at time zone 'America/Sao_Paulo')::time;
begin
    return exists (
        select 1 from horario_funcionamento f
         where f.unidade_id = p_unidade_id
           and f.dia_semana = fn_dia_semana_local(p_momento)
           and v_hora >= f.abre and v_hora < f.fecha
    );
end;
$$;

-- Recalcula a espera estimada de uma unidade.
-- Média ponderada dos registros das últimas 2 horas:
--   * quem ainda aguarda vale como evidência atual (máximo entre percepção e tempo já esperado);
--   * espera medida (chegada até atendimento) vale o dobro da percepção;
--   * registros perdem peso com o tempo (meia-vida aproximada de 30 minutos);
--   * sem registros recentes, usa a média histórica do dia e da hora.
create or replace procedure prc_recalcular_situacao(
    p_unidade_id bigint,
    p_agora      timestamptz default now()
)
language plpgsql security definer set search_path = public as $$
declare
    v_soma_peso   numeric;
    v_media       numeric;
    v_qtd         integer;
    v_aguardando  integer;
    v_espera      integer;
    v_fonte       text;
    v_confianca   integer;
begin
    select sum(peso_final), sum(minutos * peso_final) / nullif(sum(peso_final), 0), count(*)
      into v_soma_peso, v_media, v_qtd
      from (
        select case
                   when r.status = 'aguardando' and r.tipo = 'checkin' then
                       greatest(fn_minutos_por_tamanho(r.tamanho_fila),
                                extract(epoch from (p_agora - r.chegada_em)) / 60)
                   else coalesce(r.espera_real_min, fn_minutos_por_tamanho(r.tamanho_fila))
               end as minutos,
               r.peso
               * case when r.espera_real_min is not null then 2.0 else 1.0 end
               * case
                     when r.status = 'aguardando' and r.tipo = 'checkin' then 1.0
                     else exp(-extract(epoch from (p_agora - coalesce(r.atendido_em, r.chegada_em))) / 60 / 45)
                 end as peso_final
          from registro_fila r
         where r.unidade_id = p_unidade_id
           and r.status <> 'expirado'
           and coalesce(r.atendido_em, r.chegada_em) > p_agora - interval '2 hours'
           and r.chegada_em <= p_agora
      ) amostras;

    select count(*) into v_aguardando
      from registro_fila
     where unidade_id = p_unidade_id and status = 'aguardando' and tipo = 'checkin';

    if coalesce(v_qtd, 0) > 0 then
        v_espera    := round(v_media);
        v_fonte     := 'tempo_real';
        v_confianca := least(100, round(v_soma_peso * 20));
    else
        select media_espera_min, least(40, qtd_amostras * 4)
          into v_espera, v_confianca
          from historico_espera
         where unidade_id = p_unidade_id
           and dia_semana = fn_dia_semana_local(p_agora)
           and hora = fn_hora_local(p_agora);

        if found then
            v_fonte := 'historico';
        else
            v_espera := null;
            v_fonte := 'sem_dados';
            v_confianca := 0;
        end if;
    end if;

    insert into situacao_unidade as s
        (unidade_id, espera_estimada_min, nivel, fonte, confianca,
         pessoas_aguardando, qtd_registros, atualizado_em)
    values
        (p_unidade_id, v_espera, fn_nivel_por_minutos(v_espera), v_fonte, v_confianca,
         v_aguardando, coalesce(v_qtd, 0), p_agora)
    on conflict (unidade_id) do update
       set espera_estimada_min = excluded.espera_estimada_min,
           nivel               = excluded.nivel,
           fonte               = excluded.fonte,
           confianca           = excluded.confianca,
           pessoas_aguardando  = excluded.pessoas_aguardando,
           qtd_registros       = excluded.qtd_registros,
           atualizado_em       = excluded.atualizado_em;
end;
$$;

-- Manutenção periódica: encerra check-ins esquecidos e atualiza as unidades afetadas.
-- Usa cursor explícito e trata erro por unidade para que uma falha não interrompa as demais.
create or replace procedure prc_expirar_registros(
    p_agora       timestamptz default now(),
    p_limite      interval    default interval '6 hours'
)
language plpgsql security definer set search_path = public as $$
declare
    c_unidades cursor for
        select id from unidade where ativo;
    v_expirados integer;
begin
    update registro_fila
       set status = 'expirado'
     where status = 'aguardando'
       and chegada_em < p_agora - p_limite;
    get diagnostics v_expirados = row_count;

    for r in c_unidades loop
        begin
            call prc_recalcular_situacao(r.id, p_agora);
        exception when others then
            raise warning 'Falha ao recalcular a unidade %: %', r.id, sqlerrm;
        end;
    end loop;

    raise notice 'Registros expirados: %', v_expirados;
end;
$$;

-- Consolida o histórico por unidade, dia da semana e hora (base da previsão de melhor horário).
create or replace procedure prc_consolidar_historico(p_dias integer default 60)
language plpgsql security definer set search_path = public as $$
begin
    insert into historico_espera as h
        (unidade_id, dia_semana, hora, media_espera_min, qtd_amostras, atualizado_em)
    select r.unidade_id,
           fn_dia_semana_local(r.chegada_em),
           fn_hora_local(r.chegada_em),
           round(avg(coalesce(r.espera_real_min, fn_minutos_por_tamanho(r.tamanho_fila)))),
           count(*),
           now()
      from registro_fila r
     where r.chegada_em > now() - make_interval(days => p_dias)
       and r.status <> 'expirado'
     group by 1, 2, 3
    on conflict (unidade_id, dia_semana, hora) do update
       set media_espera_min = excluded.media_espera_min,
           qtd_amostras     = excluded.qtd_amostras,
           atualizado_em    = excluded.atualizado_em;
end;
$$;

-- Previsão: espera média por hora em um dia da semana, dentro do horário de funcionamento.
create or replace function fn_melhor_horario(p_unidade_id bigint, p_dia_semana smallint)
returns table (hora smallint, media_espera_min integer, qtd_amostras integer, melhor boolean)
language plpgsql stable as $$
begin
    return query
    select h.hora, h.media_espera_min, h.qtd_amostras,
           h.media_espera_min = min(h.media_espera_min) over () as melhor
      from historico_espera h
      left join horario_funcionamento f
             on f.unidade_id = h.unidade_id and f.dia_semana = h.dia_semana
     where h.unidade_id = p_unidade_id
       and h.dia_semana = p_dia_semana
       and (f.unidade_id is null
            or make_time(h.hora, 0, 0) >= f.abre and make_time(h.hora, 0, 0) < f.fecha)
     order by h.hora;
end;
$$;

-- Recomendação: unidades próximas ordenadas pelo tempo total (deslocamento + espera).
-- Deslocamento estimado a 20 km/h, média urbana conservadora.
create or replace function fn_recomendar_unidades(
    p_latitude        double precision,
    p_longitude       double precision,
    p_tipo_unidade_id smallint default null,
    p_servico_id      smallint default null,
    p_raio_km         double precision default 10
)
returns table (
    unidade_id          bigint,
    nome                text,
    tipo                text,
    distancia_km        numeric,
    espera_estimada_min integer,
    deslocamento_min    integer,
    tempo_total_min     integer,
    nivel               text,
    confianca           smallint
)
language plpgsql stable as $$
begin
    return query
    select u.id, u.nome, t.nome,
           round(d.km::numeric, 1),
           s.espera_estimada_min,
           round(d.km * 3)::integer,
           (round(d.km * 3) + s.espera_estimada_min)::integer,
           coalesce(s.nivel, 'sem_dados'),
           coalesce(s.confianca, 0::smallint)
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      left join situacao_unidade s on s.unidade_id = u.id
      cross join lateral (
          select fn_distancia_km(p_latitude, p_longitude, u.latitude, u.longitude) as km
      ) d
     where u.ativo
       and d.km <= p_raio_km
       and (p_tipo_unidade_id is null or u.tipo_unidade_id = p_tipo_unidade_id)
       and (p_servico_id is null or exists (
               select 1 from unidade_servico us
                where us.unidade_id = u.id and us.servico_id = p_servico_id))
     order by (round(d.km * 3) + s.espera_estimada_min) nulls last, d.km;
end;
$$;

-- Registra a confirmação de um relato por outro usuário.
create or replace function fn_confirmar_relato(p_relato_id bigint, p_usuario_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
    v_autor uuid;
    v_total integer;
begin
    select usuario_id into v_autor from relato where id = p_relato_id and expira_em > now();
    if not found then
        raise exception 'Relato inexistente ou expirado' using errcode = 'PR002';
    end if;
    if v_autor = p_usuario_id then
        raise exception 'Não é possível confirmar o próprio relato' using errcode = 'PR003';
    end if;

    insert into relato_confirmacao (relato_id, usuario_id) values (p_relato_id, p_usuario_id);

    select confirmacoes into v_total from relato where id = p_relato_id;
    return v_total;
exception
    when unique_violation then
        raise exception 'Você já confirmou este relato' using errcode = 'PR004';
end;
$$;

-- Indicadores gerais para o painel.
create or replace function fn_painel_geral()
returns table (
    unidades_monitoradas   bigint,
    unidades_com_dados     bigint,
    registros_hoje         bigint,
    espera_media_geral_min integer,
    colaboradores_7_dias   bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
    return query
    select (select count(*) from unidade where ativo),
           (select count(*) from situacao_unidade where fonte = 'tempo_real'),
           (select count(*) from registro_fila
             where (chegada_em at time zone 'America/Sao_Paulo')::date
                 = (now() at time zone 'America/Sao_Paulo')::date),
           (select round(avg(espera_estimada_min))::integer
              from situacao_unidade where fonte = 'tempo_real'),
           (select count(distinct usuario_id) from registro_fila
             where chegada_em > now() - interval '7 days');
end;
$$;

-- Visão que alimenta o mapa: uma linha por unidade com tudo o que o marcador precisa.
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
           and r.tipo <> 'atendimento_normal') as relatos_ativos
  from unidade u
  join tipo_unidade t on t.id = u.tipo_unidade_id
  left join situacao_unidade s on s.unidade_id = u.id
 where u.ativo;

-- Indicadores por unidade nos últimos 7 dias.
create or replace view vw_indicadores_unidade as
select u.id as unidade_id, u.nome, t.nome as tipo,
       count(r.id) as registros_7_dias,
       round(avg(coalesce(r.espera_real_min, fn_minutos_por_tamanho(r.tamanho_fila)))) as espera_media_min,
       max(r.espera_real_min) as maior_espera_medida_min,
       (select h.hora from historico_espera h
         where h.unidade_id = u.id
         order by h.media_espera_min desc, h.qtd_amostras desc limit 1) as hora_pico
  from unidade u
  join tipo_unidade t on t.id = u.tipo_unidade_id
  left join registro_fila r
         on r.unidade_id = u.id
        and r.chegada_em > now() - interval '7 days'
        and r.status <> 'expirado'
 where u.ativo
 group by u.id, u.nome, t.nome;

create or replace view vw_ranking_colaboradores as
select row_number() over (order by us.pontos desc, us.criado_em) as posicao,
       us.id as usuario_id, us.nome, us.pontos, us.nivel,
       (select count(*) from registro_fila r where r.usuario_id = us.id) as total_registros
  from usuario us
 where us.pontos > 0;

-- ===== 03_triggers.sql =====
-- Passa Rápido: triggers de automação

-- Toda unidade nasce com sua linha de situação, para o mapa nunca ficar sem marcador.
create or replace function trg_fn_unidade_cria_situacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into situacao_unidade (unidade_id) values (new.id)
    on conflict (unidade_id) do nothing;
    return new;
end;
$$;

create trigger trg_unidade_cria_situacao
after insert on unidade
for each row execute function trg_fn_unidade_cria_situacao();

-- Validação e preparo do registro antes de gravar.
create or replace function trg_fn_registro_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    -- Bloqueia registros repetidos do mesmo usuário na mesma unidade em 10 minutos.
    if exists (
        select 1 from registro_fila
         where usuario_id = new.usuario_id
           and unidade_id = new.unidade_id
           and chegada_em > new.chegada_em - interval '10 minutes'
           and chegada_em <= new.chegada_em
    ) then
        raise exception 'Você já registrou esta unidade há menos de 10 minutos'
            using errcode = 'PR001';
    end if;

    new.peso := fn_peso_usuario(new.usuario_id);

    if new.tipo = 'observacao' then
        -- Observação é um retrato do momento, não uma permanência na fila.
        new.status := 'concluido';
    else
        -- Um usuário só pode estar em uma fila por vez.
        update registro_fila
           set status = 'desistiu', saida_em = new.chegada_em
         where usuario_id = new.usuario_id
           and status = 'aguardando'
           and chegada_em <= new.chegada_em;
    end if;

    return new;
end;
$$;

create trigger trg_registro_antes_inserir
before insert on registro_fila
for each row execute function trg_fn_registro_antes_inserir();

-- Ao marcar o atendimento, calcula a espera real e avança o status.
create or replace function trg_fn_registro_antes_atualizar() returns trigger
language plpgsql as $$
begin
    if new.atendido_em is not null and old.atendido_em is null then
        new.espera_real_min := ceil(extract(epoch from (new.atendido_em - new.chegada_em)) / 60);
        if new.status = 'aguardando' then
            new.status := 'atendido';
        end if;
    end if;

    if new.saida_em is not null and old.saida_em is null and new.status = 'atendido' then
        new.status := 'concluido';
    end if;

    return new;
end;
$$;

create trigger trg_registro_antes_atualizar
before update on registro_fila
for each row execute function trg_fn_registro_antes_atualizar();

-- Depois de gravar: recalcula a situação da unidade e credita pontos ao colaborador.
create or replace function trg_fn_registro_depois() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    call prc_recalcular_situacao(new.unidade_id, greatest(now(), new.chegada_em));

    if tg_op = 'INSERT' then
        insert into movimento_pontos (usuario_id, pontos, motivo)
        values (new.usuario_id,
                case new.tipo when 'checkin' then 5 else 3 end,
                new.tipo);
    elsif new.atendido_em is not null and old.atendido_em is null then
        insert into movimento_pontos (usuario_id, pontos, motivo)
        values (new.usuario_id, 10, 'atendimento_confirmado');
    end if;

    return null;
end;
$$;

create trigger trg_registro_depois
after insert or update of status, atendido_em, saida_em on registro_fila
for each row execute function trg_fn_registro_depois();

-- Extrato de pontos atualiza o saldo e o nível de reputação do usuário.
create or replace function trg_fn_pontos_atualiza_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    update usuario
       set pontos = greatest(0, pontos + new.pontos),
           nivel  = fn_nivel_por_pontos(greatest(0, pontos + new.pontos))
     where id = new.usuario_id;
    return null;
end;
$$;

create trigger trg_pontos_atualiza_usuario
after insert on movimento_pontos
for each row execute function trg_fn_pontos_atualiza_usuario();

-- Alerta de fila baixa: quando a espera cruza para baixo do limite de quem favoritou.
-- Intervalo mínimo de 1 hora entre alertas da mesma unidade para o mesmo usuário.
create or replace function trg_fn_situacao_alerta_favoritos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_nome text;
begin
    if new.fonte <> 'tempo_real' or new.espera_estimada_min is null then
        return null;
    end if;

    select nome into v_nome from unidade where id = new.unidade_id;

    with alvos as (
        update favorito f
           set ultimo_alerta_em = new.atualizado_em
         where f.unidade_id = new.unidade_id
           and f.alerta_ativo
           and new.espera_estimada_min <= f.limite_espera_min
           and (old.espera_estimada_min is null
                or old.fonte <> 'tempo_real'
                or old.espera_estimada_min > f.limite_espera_min)
           and (f.ultimo_alerta_em is null
                or f.ultimo_alerta_em < new.atualizado_em - interval '1 hour')
        returning f.usuario_id
    )
    insert into notificacao (usuario_id, unidade_id, titulo, mensagem)
    select a.usuario_id, new.unidade_id,
           'Fila baixa agora',
           format('%s está com espera estimada de %s min.', v_nome, new.espera_estimada_min)
      from alvos a;

    return null;
end;
$$;

create trigger trg_situacao_alerta_favoritos
after update of espera_estimada_min on situacao_unidade
for each row execute function trg_fn_situacao_alerta_favoritos();

-- Relatos e avaliações também valem pontos.
create or replace function trg_fn_relato_pontos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into movimento_pontos (usuario_id, pontos, motivo)
    values (new.usuario_id, 3, 'relato');
    return null;
end;
$$;

create trigger trg_relato_pontos
after insert on relato
for each row execute function trg_fn_relato_pontos();

-- Confirmação de relato: soma no contador, estende a validade e premia o autor.
create or replace function trg_fn_confirmacao_relato() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_autor uuid;
begin
    update relato
       set confirmacoes = confirmacoes + 1,
           expira_em = least(expira_em + interval '1 hour', criado_em + interval '12 hours')
     where id = new.relato_id
    returning usuario_id into v_autor;

    insert into movimento_pontos (usuario_id, pontos, motivo)
    values (v_autor, 2, 'relato_confirmado');
    return null;
end;
$$;

create trigger trg_confirmacao_relato
after insert on relato_confirmacao
for each row execute function trg_fn_confirmacao_relato();

create or replace function trg_fn_avaliacao_pontos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into movimento_pontos (usuario_id, pontos, motivo)
    values (new.usuario_id, 2, 'avaliacao');
    return null;
end;
$$;

create trigger trg_avaliacao_pontos
after insert on avaliacao
for each row execute function trg_fn_avaliacao_pontos();

-- ===== 04_seed.sql =====
-- Passa Rápido: dados de demonstração (cidade de São Paulo)
-- ATENÇÃO: as unidades abaixo têm localização APROXIMADA por bairro e as filas são simuladas.
-- Servem para demonstrar o app; para uso real, carregar as unidades de fontes oficiais.

select setseed(0.42);

insert into tipo_unidade (nome, icone, cor_hex) values
    ('UPA',            'emergency',        '#C62828'),
    ('Pronto-socorro', 'local_hospital',   '#AD1457'),
    ('UBS',            'medical_services', '#2E7D32'),
    ('Poupatempo',     'badge',            '#1565C0'),
    ('INSS',           'account_balance',  '#EF6C00'),
    ('CRAS',           'diversity_3',      '#6A1B9A');

insert into servico (nome, descricao, documentos_necessarios) values
    ('Clínico geral',            'Atendimento médico de urgência para adultos',  'Documento com foto e cartão do SUS'),
    ('Pediatria',                'Atendimento médico de urgência para crianças', 'Documento do responsável, certidão ou RG da criança e cartão do SUS'),
    ('Ortopedia',                'Fraturas, torções e dores musculares',         'Documento com foto e cartão do SUS'),
    ('Vacinação',                'Vacinas do calendário nacional',               'Documento com foto e caderneta de vacinação'),
    ('Medicação e curativos',    'Aplicação de medicamentos e troca de curativos', 'Documento com foto e receita médica'),
    ('Carteira de identidade',   'Primeira via e segunda via do RG',             'Certidão de nascimento ou casamento e CPF'),
    ('CNH',                      'Renovação e segunda via da habilitação',       'CNH atual, CPF e comprovante de endereço'),
    ('Seguro-desemprego',        'Solicitação do benefício',                     'Requerimento do empregador, carteira de trabalho e documento com foto'),
    ('Perícia médica',           'Perícia para benefícios por incapacidade',     'Documento com foto, laudos e exames'),
    ('Aposentadoria e benefícios', 'Orientação e requerimento de benefícios',    'Documento com foto, CPF e carteira de trabalho'),
    ('Cadastro Único',           'Inscrição e atualização do CadÚnico',          'CPF ou título de eleitor de todos os moradores e comprovante de endereço'),
    ('Bolsa Família',            'Orientação e acompanhamento do benefício',     'Documento com foto e número do NIS');

insert into unidade (tipo_unidade_id, nome, endereco, bairro, cidade, uf, latitude, longitude)
select t.id, v.nome, 'Localização aproximada (dado de demonstração)', v.bairro, 'São Paulo', 'SP', v.lat, v.lng
  from (values
    ('UPA',            'UPA Vila Mariana',                'Vila Mariana',  -23.5893, -46.6350),
    ('UPA',            'UPA Santo Amaro',                 'Santo Amaro',   -23.6536, -46.7106),
    ('UPA',            'UPA Tatuapé',                     'Tatuapé',       -23.5403, -46.5766),
    ('UPA',            'UPA Campo Limpo',                 'Campo Limpo',   -23.6490, -46.7590),
    ('UPA',            'UPA Pirituba',                    'Pirituba',      -23.4870, -46.7260),
    ('Pronto-socorro', 'Pronto-Socorro Lapa',             'Lapa',          -23.5270, -46.7030),
    ('Pronto-socorro', 'Pronto-Socorro Santana',          'Santana',       -23.5020, -46.6250),
    ('UBS',            'UBS Sé',                          'Sé',            -23.5480, -46.6340),
    ('UBS',            'UBS Pinheiros',                   'Pinheiros',     -23.5630, -46.6900),
    ('UBS',            'UBS Itaquera',                    'Itaquera',      -23.5360, -46.4560),
    ('UBS',            'UBS Butantã',                     'Butantã',       -23.5710, -46.7080),
    ('UBS',            'UBS Mooca',                       'Mooca',         -23.5600, -46.5990),
    ('Poupatempo',     'Poupatempo Sé',                   'Sé',            -23.5499, -46.6310),
    ('Poupatempo',     'Poupatempo Santo Amaro',          'Santo Amaro',   -23.6510, -46.7080),
    ('Poupatempo',     'Poupatempo Itaquera',             'Itaquera',      -23.5420, -46.4710),
    ('Poupatempo',     'Poupatempo Lapa',                 'Lapa',          -23.5200, -46.7010),
    ('INSS',           'Agência INSS Centro',             'República',     -23.5440, -46.6390),
    ('INSS',           'Agência INSS Santana',            'Santana',       -23.5010, -46.6280),
    ('INSS',           'Agência INSS Santo Amaro',        'Santo Amaro',   -23.6480, -46.7040),
    ('INSS',           'Agência INSS Tatuapé',            'Tatuapé',       -23.5380, -46.5650),
    ('CRAS',           'CRAS Sé',                         'Sé',            -23.5465, -46.6365),
    ('CRAS',           'CRAS Capão Redondo',              'Capão Redondo', -23.6690, -46.7790),
    ('CRAS',           'CRAS Brasilândia',                'Brasilândia',   -23.4690, -46.6900)
  ) as v (tipo, nome, bairro, lat, lng)
  join tipo_unidade t on t.nome = v.tipo;

insert into unidade_servico (unidade_id, servico_id)
select u.id, s.id
  from unidade u
  join tipo_unidade t on t.id = u.tipo_unidade_id
  join servico s on
       (t.nome in ('UPA', 'Pronto-socorro')
            and s.nome in ('Clínico geral', 'Pediatria', 'Ortopedia', 'Medicação e curativos'))
    or (t.nome = 'UBS'
            and s.nome in ('Clínico geral', 'Pediatria', 'Vacinação', 'Medicação e curativos'))
    or (t.nome = 'Poupatempo'
            and s.nome in ('Carteira de identidade', 'CNH', 'Seguro-desemprego'))
    or (t.nome = 'INSS'
            and s.nome in ('Perícia médica', 'Aposentadoria e benefícios'))
    or (t.nome = 'CRAS'
            and s.nome in ('Cadastro Único', 'Bolsa Família'));

-- UPA e pronto-socorro: 24 horas. Demais: dias úteis das 8h às 17h. Poupatempo abre aos sábados.
insert into horario_funcionamento (unidade_id, dia_semana, abre, fecha)
select u.id, d, time '00:00', time '23:59:59'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id, generate_series(0, 6) d
 where t.nome in ('UPA', 'Pronto-socorro')
union all
select u.id, d, time '08:00', time '17:00'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id, generate_series(1, 5) d
 where t.nome not in ('UPA', 'Pronto-socorro')
union all
select u.id, 6, time '09:00', time '13:00'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id
 where t.nome = 'Poupatempo';

insert into usuario (id, nome, pontos, nivel) values
    ('00000000-0000-4000-8000-000000000001', 'Ana Souza',        320, 'confiavel'),
    ('00000000-0000-4000-8000-000000000002', 'Bruno Lima',       245, 'confiavel'),
    ('00000000-0000-4000-8000-000000000003', 'Carla Mendes',     180, 'colaborador'),
    ('00000000-0000-4000-8000-000000000004', 'Diego Rocha',      130, 'colaborador'),
    ('00000000-0000-4000-8000-000000000005', 'Elaine Costa',      95, 'colaborador'),
    ('00000000-0000-4000-8000-000000000006', 'Fábio Santos',      60, 'colaborador'),
    ('00000000-0000-4000-8000-000000000007', 'Gabriela Alves',    40, 'iniciante'),
    ('00000000-0000-4000-8000-000000000008', 'Henrique Dias',     25, 'iniciante'),
    ('00000000-0000-4000-8000-000000000009', 'Isabela Ferreira',  15, 'iniciante'),
    ('00000000-0000-4000-8000-000000000010', 'João Pereira',      10, 'iniciante'),
    ('00000000-0000-4000-8000-000000000011', 'Karina Oliveira',    5, 'iniciante'),
    ('00000000-0000-4000-8000-000000000012', 'Lucas Martins',      0, 'iniciante');

-- Carga em massa sem disparar os triggers linha a linha; a consolidação é feita ao final.
alter table registro_fila disable trigger user;

-- Histórico dos últimos 21 dias: dois registros por hora de funcionamento em cada unidade.
-- A espera segue uma curva com picos às 10h e às 15h, maior às segundas e menor no fim de semana.
-- O CRAS Brasilândia fica sem histórico para demonstrar o estado "sem dados".
insert into registro_fila
    (unidade_id, usuario_id, tipo, tamanho_fila, status, chegada_em, atendido_em, saida_em, espera_real_min, peso)
select g.unidade_id, g.usuario_id, 'checkin',
       case when g.espera <= 5 then 'sem_fila' when g.espera <= 25 then 'curta'
            when g.espera <= 60 then 'media' when g.espera <= 110 then 'longa' else 'lotada' end,
       'concluido',
       g.chegada, g.chegada + make_interval(mins => g.espera),
       g.chegada + make_interval(mins => g.espera + 20),
       g.espera, 1.0
  from (
    select u.id as unidade_id,
           ('00000000-0000-4000-8000-0000000000' || lpad((1 + floor(random() * 12))::int::text, 2, '0'))::uuid as usuario_id,
           ((date_trunc('day', now() at time zone 'America/Sao_Paulo')
                - make_interval(days => d) + make_interval(hours => h, mins => (floor(random() * 50))::int))
                at time zone 'America/Sao_Paulo') as chegada,
           greatest(0, round(
               case t.nome when 'UPA' then 55 when 'Pronto-socorro' then 80 when 'UBS' then 30
                           when 'Poupatempo' then 28 when 'INSS' then 42 else 18 end
               * (0.45 + 0.9 * exp(-((h - 10) ^ 2) / 8.0) + 0.7 * exp(-((h - 15) ^ 2) / 8.0)
                       + case when t.nome in ('UPA', 'Pronto-socorro') then 0.5 * exp(-((h - 20) ^ 2) / 6.0) else 0 end)
               * case extract(dow from (now() at time zone 'America/Sao_Paulo')::date - d)
                      when 1 then 1.3 when 5 then 1.1 when 0 then 0.75 when 6 then 0.8 else 1.0 end
               * (0.7 + random() * 0.6)
           ))::int as espera
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(1, 21) d
      cross join generate_series(0, 23) h
      cross join generate_series(1, 2) amostra
      join horario_funcionamento f
        on f.unidade_id = u.id
       and f.dia_semana = extract(dow from (now() at time zone 'America/Sao_Paulo')::date - d)
       and make_time(h, 0, 0) >= f.abre and make_time(h, 0, 0) < f.fecha
     where u.nome <> 'CRAS Brasilândia'
  ) g;

-- Movimento da última hora, para o mapa abrir com dados em tempo real.
insert into registro_fila
    (unidade_id, usuario_id, tipo, tamanho_fila, status, chegada_em, atendido_em, espera_real_min, peso)
select u.id,
       ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid,
       v.tipo, v.tamanho, v.status,
       now() - make_interval(mins => v.min_atras),
       case when v.espera is not null then now() - make_interval(mins => v.min_atras - v.espera) end,
       v.espera,
       v.peso
  from (values
    ('UPA Vila Mariana',         1, 'checkin',    'lotada',   'aguardando', 95,  null, 2.0),
    ('UPA Vila Mariana',         4, 'checkin',    'longa',    'atendido',   110, 100,  1.5),
    ('UPA Vila Mariana',         7, 'observacao', 'lotada',   'concluido',  12,  null, 1.0),
    ('UPA Santo Amaro',          2, 'checkin',    'media',    'atendido',   50,  38,   2.0),
    ('UPA Santo Amaro',          8, 'observacao', 'media',    'concluido',  9,   null, 1.0),
    ('UPA Tatuapé',              3, 'checkin',    'curta',    'atendido',   30,  12,   1.5),
    ('UPA Tatuapé',              9, 'observacao', 'curta',    'concluido',  6,   null, 1.0),
    ('UPA Campo Limpo',          5, 'checkin',    'longa',    'aguardando', 62,  null, 1.5),
    ('UPA Pirituba',             6, 'observacao', 'sem_fila', 'concluido',  14,  null, 1.5),
    ('Pronto-Socorro Lapa',      10, 'checkin',   'lotada',   'aguardando', 130, null, 1.0),
    ('Pronto-Socorro Lapa',      2, 'observacao', 'lotada',   'concluido',  20,  null, 2.0),
    ('Pronto-Socorro Santana',   11, 'checkin',   'media',    'atendido',   70,  45,   1.0),
    ('UBS Sé',                   1, 'observacao', 'curta',    'concluido',  18,  null, 2.0),
    ('UBS Pinheiros',            3, 'checkin',    'sem_fila', 'atendido',   25,  4,    1.5),
    ('UBS Itaquera',             4, 'checkin',    'media',    'aguardando', 33,  null, 1.5),
    ('Poupatempo Sé',            5, 'checkin',    'longa',    'atendido',   90,  72,   1.5),
    ('Poupatempo Sé',            12, 'observacao','longa',    'concluido',  8,   null, 1.0),
    ('Poupatempo Santo Amaro',   6, 'checkin',    'curta',    'atendido',   40,  18,   1.5),
    ('Poupatempo Itaquera',      7, 'observacao', 'media',    'concluido',  22,  null, 1.0),
    ('Agência INSS Centro',      8, 'checkin',    'longa',    'aguardando', 75,  null, 1.0),
    ('Agência INSS Santana',     9, 'checkin',    'curta',    'atendido',   35,  14,   1.0),
    ('CRAS Sé',                  10, 'observacao','sem_fila', 'concluido',  16,  null, 1.0)
  ) as v (unidade, usuario, tipo, tamanho, status, min_atras, espera, peso)
  join unidade u on u.nome = v.unidade;

alter table registro_fila enable trigger user;

call prc_consolidar_historico(60);
call prc_expirar_registros();

insert into relato (unidade_id, usuario_id, tipo, descricao)
select u.id, ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid, v.tipo, v.descricao
  from (values
    ('UPA Vila Mariana',    1, 'sem_medico',         'Sem pediatra no plantão desta tarde'),
    ('Poupatempo Sé',       5, 'sistema_fora',       'Sistema do RG fora do ar, sem previsão'),
    ('UBS Pinheiros',       3, 'atendimento_normal', 'Atendimento rápido e vacinas disponíveis'),
    ('UBS Itaquera',        4, 'sem_vacina',         'Vacina da gripe em falta'),
    ('Agência INSS Centro', 8, 'sem_senha',          'Senhas do dia esgotadas às 10h')
  ) as v (unidade, usuario, tipo, descricao)
  join unidade u on u.nome = v.unidade;

insert into avaliacao (unidade_id, usuario_id, nota, comentario)
select u.id, ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid, v.nota, v.comentario
  from (values
    ('UPA Vila Mariana',  1, 3, 'Atendimento bom, mas a espera é longa'),
    ('UPA Vila Mariana',  4, 2, 'Fiquei quase duas horas esperando'),
    ('UPA Tatuapé',       3, 5, 'Fui atendido rápido'),
    ('UBS Pinheiros',     3, 5, 'Equipe atenciosa'),
    ('Poupatempo Sé',     5, 4, 'Organizado, mas cheio no horário de almoço'),
    ('Poupatempo Lapa',   2, 5, 'Resolvi tudo em meia hora')
  ) as v (unidade, usuario, nota, comentario)
  join unidade u on u.nome = v.unidade;

insert into favorito (usuario_id, unidade_id, limite_espera_min)
select '00000000-0000-4000-8000-000000000012', u.id, 30
  from unidade u where u.nome in ('UPA Vila Mariana', 'Poupatempo Sé');

-- ===== 05_supabase.sql =====
-- Passa Rápido: configuração específica do Supabase (autenticação, segurança por linha e tempo real).
-- Executar somente no Supabase, depois dos scripts 01 a 04.

-- Cria o perfil automaticamente quando alguém se cadastra.
create or replace function trg_fn_novo_usuario_auth() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into usuario (id, nome)
    values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'nome', ''), 'Cidadão'))
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists trg_novo_usuario_auth on auth.users;
create trigger trg_novo_usuario_auth
after insert on auth.users
for each row execute function trg_fn_novo_usuario_auth();

-- O autor de cada linha é sempre quem está autenticado.
alter table registro_fila alter column usuario_id set default auth.uid();
alter table relato        alter column usuario_id set default auth.uid();
alter table favorito      alter column usuario_id set default auth.uid();
alter table avaliacao     alter column usuario_id set default auth.uid();

-- Confirmação de relato sempre em nome do usuário autenticado.
create or replace function confirmar_relato(p_relato_id bigint) returns integer
language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then
        raise exception 'É preciso entrar para confirmar um relato' using errcode = 'PR005';
    end if;
    return fn_confirmar_relato(p_relato_id, auth.uid());
end;
$$;

revoke execute on function fn_confirmar_relato(bigint, uuid) from public, anon, authenticated;
revoke execute on procedure prc_recalcular_situacao(bigint, timestamptz) from public, anon, authenticated;
revoke execute on procedure prc_expirar_registros(timestamptz, interval) from public, anon, authenticated;
revoke execute on procedure prc_consolidar_historico(integer) from public, anon, authenticated;

-- Segurança por linha.
alter table tipo_unidade          enable row level security;
alter table unidade               enable row level security;
alter table servico               enable row level security;
alter table unidade_servico       enable row level security;
alter table horario_funcionamento enable row level security;
alter table situacao_unidade      enable row level security;
alter table historico_espera      enable row level security;
alter table usuario               enable row level security;
alter table registro_fila         enable row level security;
alter table relato                enable row level security;
alter table relato_confirmacao    enable row level security;
alter table favorito              enable row level security;
alter table notificacao           enable row level security;
alter table avaliacao             enable row level security;
alter table movimento_pontos      enable row level security;

-- Dados públicos: qualquer pessoa pode consultar o mapa sem cadastro.
create policy leitura_publica on tipo_unidade          for select using (true);
create policy leitura_publica on unidade               for select using (true);
create policy leitura_publica on servico               for select using (true);
create policy leitura_publica on unidade_servico       for select using (true);
create policy leitura_publica on horario_funcionamento for select using (true);
create policy leitura_publica on situacao_unidade      for select using (true);
create policy leitura_publica on historico_espera      for select using (true);
create policy leitura_publica on usuario               for select using (true);
create policy leitura_publica on relato                for select using (true);
create policy leitura_publica on avaliacao             for select using (true);

-- Dados pessoais: cada usuário só vê e altera o que é seu.
create policy registro_leitura    on registro_fila for select to authenticated using (usuario_id = auth.uid());
create policy registro_insercao   on registro_fila for insert to authenticated with check (usuario_id = auth.uid());
create policy registro_alteracao  on registro_fila for update to authenticated
    using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

create policy relato_insercao     on relato for insert to authenticated with check (usuario_id = auth.uid());

create policy favorito_proprio    on favorito for all to authenticated
    using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

create policy notificacao_leitura   on notificacao for select to authenticated using (usuario_id = auth.uid());
create policy notificacao_alteracao on notificacao for update to authenticated
    using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

create policy avaliacao_insercao  on avaliacao for insert to authenticated with check (usuario_id = auth.uid());
create policy avaliacao_alteracao on avaliacao for update to authenticated
    using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

create policy perfil_alteracao    on usuario for update to authenticated
    using (id = auth.uid()) with check (id = auth.uid());

create policy pontos_leitura      on movimento_pontos for select to authenticated using (usuario_id = auth.uid());

-- Colunas calculadas pelo banco não podem ser gravadas pelo aplicativo.
revoke insert, update on registro_fila from anon, authenticated;
grant insert (unidade_id, servico_id, tipo, tamanho_fila) on registro_fila to authenticated;
grant update (atendido_em, saida_em, status) on registro_fila to authenticated;

revoke insert, update on usuario from anon, authenticated;
grant update (nome) on usuario to authenticated;

revoke update on notificacao from anon, authenticated;
grant update (lida) on notificacao to authenticated;

revoke insert, update, delete on situacao_unidade, historico_espera, movimento_pontos,
    relato_confirmacao from anon, authenticated;

-- Tempo real: o mapa, os alertas e os relatos chegam ao app sem recarregar.
alter publication supabase_realtime add table situacao_unidade;
alter publication supabase_realtime add table notificacao;
alter publication supabase_realtime add table relato;

-- Rotinas agendadas (exige a extensão pg_cron, ativada em Database > Extensions).
create extension if not exists pg_cron;
select cron.schedule('passa-rapido-expirar',    '*/10 * * * *', 'call prc_expirar_registros()');
select cron.schedule('passa-rapido-consolidar', '15 6 * * *',   'call prc_consolidar_historico(60)');
