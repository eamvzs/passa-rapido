-- Passa Rápido: supabase_instalar.sql
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em Run.

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

-- Simulador de movimento para demonstração.
-- Gera registros de usuários fictícios em unidades abertas, com espera próxima da média histórica
-- do horário. Passa pelos mesmos triggers dos registros reais, então o mapa se atualiza sozinho.
-- Desligar em produção: select cron.unschedule('passa-rapido-simulador');
create or replace procedure prc_simular_movimento(p_quantidade integer default 4)
language plpgsql security definer set search_path = public as $$
declare
    c_alvos cursor for
        select u.id as unidade_id,
               coalesce(h.media_espera_min, 30) as media
          from unidade u
          left join historico_espera h
                 on h.unidade_id = u.id
                and h.dia_semana = fn_dia_semana_local(now())
                and h.hora = fn_hora_local(now())
         where u.ativo
           and fn_unidade_aberta(u.id)
           and exists (select 1 from historico_espera x where x.unidade_id = u.id)
         order by random()
         limit p_quantidade;
    v_usuario  uuid;
    v_espera   integer;
    v_tamanho  text;
    v_registro bigint;
begin
    for alvo in c_alvos loop
        begin
            select id into v_usuario
              from usuario
             where id::text like '00000000-0000-4000-8000-%'
             order by random()
             limit 1;
            exit when v_usuario is null;

            v_espera := greatest(0, round(alvo.media * (0.6 + random() * 0.9)))::integer;
            v_tamanho := case when v_espera <= 5 then 'sem_fila' when v_espera <= 25 then 'curta'
                              when v_espera <= 60 then 'media' when v_espera <= 110 then 'longa'
                              else 'lotada' end;

            if random() < 0.5 then
                insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila)
                values (alvo.unidade_id, v_usuario, 'observacao', v_tamanho);
            else
                insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, chegada_em)
                values (alvo.unidade_id, v_usuario, 'checkin', v_tamanho,
                        now() - make_interval(mins => v_espera))
                returning id into v_registro;
                update registro_fila set atendido_em = now(), saida_em = now() where id = v_registro;
            end if;
        exception when sqlstate 'PR001' then
            null; -- mesmo usuário na mesma unidade há pouco: ignora esta rodada
        end;
    end loop;
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

-- Recomendação: unidades abertas e próximas, ordenadas pelo tempo total (deslocamento + espera).
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
       and fn_unidade_aberta(u.id)
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
    -- Chamadas vindas do aplicativo usam sempre o relógio do servidor,
    -- para que a hora errada de um celular não distorça a espera medida.
    if current_user = 'authenticated' then
        if new.atendido_em is not null and old.atendido_em is null then
            new.atendido_em := now();
        end if;
        if new.saida_em is not null and old.saida_em is null then
            new.saida_em := now();
        end if;
    end if;

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
revoke execute on procedure prc_simular_movimento(integer) from public, anon, authenticated;

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

-- O simulador de movimento (prc_simular_movimento) NÃO é agendado: o app usa apenas dados reais.
-- Para uma demonstração com movimento falso (usa os usuários fictícios do 04_seed.sql), agende por conta própria:
--   select cron.schedule('passa-rapido-simulador', '*/5 * * * *', 'call prc_simular_movimento(4)');
-- Para remover o que a simulação criou: execute 11_remover_simulacao.sql.

-- ===== 07_estrutura_dados_reais.sql =====
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

-- ===== 10_cnes.sql =====
-- Passa Rápido: suporte a unidades vindas do CNES (Cadastro Nacional de Estabelecimentos de Saúde, DATASUS).
-- Idempotente: pode ser executado mais de uma vez. Aplique depois de 07_estrutura_dados_reais.sql.

alter table unidade add column if not exists cnes_id bigint;

alter table unidade drop constraint if exists ck_unidade_origem;
alter table unidade add constraint ck_unidade_origem
    check (origem in ('demonstracao', 'openstreetmap', 'cnes'));

create unique index if not exists uq_unidade_cnes_id on unidade (cnes_id) where cnes_id is not null;

-- ===== 08_dados_reais_base.sql =====
-- Passa Rápido: parte estática da importação de unidades reais (sem dados; idempotente).
-- Aplique depois de 07_estrutura_dados_reais.sql e 10_cnes.sql e ANTES de 08_unidades_reais.sql / 10_unidades_cnes.sql.
--
-- prc_completar_unidades_reais() prepara as unidades com origem 'openstreetmap' ou 'cnes':
--   (a) vincula os serviços de cada tipo;
--   (b) cria o horário de funcionamento PADRÃO por tipo, quando a unidade não tem horário;
--   (c) gera um histórico de espera ESTIMADO (modelo, não dado de cidadãos): qtd_amostras = 0.
--       Quando houver registros reais, prc_consolidar_historico sobrescreve essas linhas
--       (on conflict ... do update) e passa a gravar a quantidade real de amostras;
--   (d) garante a linha de situação de cada unidade;
--   (e) desativa as unidades de demonstração, somente se existir ao menos uma unidade real ativa;
--   (f) recalcula a situação de cada unidade importada.

create or replace procedure prc_completar_unidades_reais()
language plpgsql security definer set search_path = public as $$
declare
    c_unidades cursor for
        select id from unidade where origem in ('openstreetmap', 'cnes') and ativo order by id;
    v_item record;
begin
    -- (a) Serviços por tipo (mesmo mapeamento dos dados de demonstração).
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
                and s.nome in ('Cadastro Único', 'Bolsa Família'))
     where u.origem in ('openstreetmap', 'cnes')
    on conflict do nothing;

    -- (b) Horário padrão, só para unidades que ainda não têm nenhum horário.
    --     UPA e pronto-socorro: 24 horas. Demais: segunda a sexta, 8h às 17h. Poupatempo também abre sábado, 9h às 13h.
    insert into horario_funcionamento (unidade_id, dia_semana, abre, fecha)
    select u.id, d.dia, time '00:00', time '23:59:59'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(0, 6) as d (dia)
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome in ('UPA', 'Pronto-socorro')
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    union all
    select u.id, d.dia, time '08:00', time '17:00'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(1, 5) as d (dia)
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome not in ('UPA', 'Pronto-socorro')
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    union all
    select u.id, 6, time '09:00', time '13:00'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome = 'Poupatempo'
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    on conflict do nothing;

    -- (c) Histórico estimado: mesma curva dos dados de demonstração (picos às 10h e 15h,
    --     pico noturno em UPA e pronto-socorro, segunda mais cheia, fim de semana mais vazio),
    --     com ruído determinístico por hash para o resultado ser reprodutível.
    --     Só entra onde ainda não existe linha: dados de cidadãos nunca são sobrescritos aqui.
    insert into historico_espera (unidade_id, dia_semana, hora, media_espera_min, qtd_amostras, atualizado_em)
    select u.id, f.dia_semana, g.hora::smallint,
           greatest(0, round(
               case t.nome when 'UPA' then 55 when 'Pronto-socorro' then 80 when 'UBS' then 30
                           when 'Poupatempo' then 28 when 'INSS' then 42 else 18 end
               * (0.45 + 0.9 * exp(-((g.hora - 10) ^ 2) / 8.0) + 0.7 * exp(-((g.hora - 15) ^ 2) / 8.0)
                       + case when t.nome in ('UPA', 'Pronto-socorro')
                              then 0.5 * exp(-((g.hora - 20) ^ 2) / 6.0) else 0 end)
               * case f.dia_semana when 1 then 1.3 when 5 then 1.1 when 0 then 0.75 when 6 then 0.8 else 1.0 end
               * (0.7 + 0.6 * ((abs(hashtext(u.id::text || '-' || f.dia_semana::text || '-' || g.hora::text)::bigint) % 1000) / 1000.0))
           ))::integer,
           0,
           now()
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      join horario_funcionamento f on f.unidade_id = u.id
      cross join generate_series(0, 23) as g (hora)
     where u.origem in ('openstreetmap', 'cnes')
       and make_time(g.hora, 0, 0) >= f.abre
       and make_time(g.hora, 0, 0) < f.fecha
    on conflict (unidade_id, dia_semana, hora) do nothing;

    -- (d) Linha de situação de cada unidade (o trigger de inserção já cria; aqui só garante).
    insert into situacao_unidade (unidade_id)
    select u.id from unidade u where u.origem in ('openstreetmap', 'cnes')
    on conflict (unidade_id) do nothing;

    -- (e) Troca os dados de demonstração pelos reais, mas nunca deixa o app sem unidades.
    if exists (select 1 from unidade where origem in ('openstreetmap', 'cnes') and ativo) then
        update unidade set ativo = false where origem = 'demonstracao' and ativo;
    end if;

    -- (f) Recalcula a situação de cada unidade importada; uma falha não interrompe as demais.
    for v_item in c_unidades loop
        begin
            call prc_recalcular_situacao(v_item.id);
        exception when others then
            raise warning 'Falha ao recalcular a unidade %: %', v_item.id, sqlerrm;
        end;
    end loop;
end;
$$;

-- Contagem de unidades por tipo e origem, para conferir a importação.
create or replace function fn_resumo_dados_reais()
returns table (tipo text, origem text, ativas bigint, total bigint)
language sql stable security definer set search_path = public as $$
    select t.nome, u.origem,
           count(*) filter (where u.ativo),
           count(*)
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
     group by t.nome, u.origem
     order by u.origem, t.nome;
$$;

-- O procedimento é de manutenção: no Supabase só o administrador deve executá-lo.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on procedure prc_completar_unidades_reais() from public, anon, authenticated;
    end if;
end;
$$;

-- ===== 09_seguranca_e_regras.sql =====
-- Passa Rápido: segurança, anti-abuso, confiabilidade e LGPD (idempotente).
-- Executar depois dos scripts 01 a 07. As partes do Supabase só rodam se o schema "auth" existir.

----------------------------------------------------------------------------------------------
-- 1. Configuração por tabela (chaves de funcionamento que o administrador pode ligar e desligar)
----------------------------------------------------------------------------------------------
create table if not exists configuracao (
    chave      text primary key,
    valor      text not null,
    descricao  text not null
);

insert into configuracao (chave, valor, descricao) values
    ('validar_localizacao', 'false',
     'Quando "true", só aceita informar a fila quem está a menos de raio_validacao_km da unidade. Deixar "false" na demonstração.'),
    ('raio_validacao_km', '0.5',
     'Distância máxima, em km, entre quem informa e a unidade quando validar_localizacao está ligado.'),
    ('max_registros_hora', '12',
     'Máximo de check-ins e observações por usuário a cada hora.'),
    ('max_relatos_hora', '3',
     'Máximo de avisos por usuário a cada hora.')
on conflict (chave) do nothing;

create or replace function fn_config(p_chave text, p_padrao text default null) returns text
language sql stable security definer set search_path = public as $$
    select coalesce((select valor from configuracao where chave = p_chave), p_padrao);
$$;

-- Verdadeiro quando a chamada vem do aplicativo (papel "authenticated" do PostgREST).
-- Rotinas do servidor (simulador, expiração, carga de dados) não passam pelas validações de cliente.
create or replace function fn_chamada_do_app() returns boolean
language sql stable as $$
    select coalesce(current_setting('role', true), '') = 'authenticated';
$$;

----------------------------------------------------------------------------------------------
-- 2. Colunas novas
----------------------------------------------------------------------------------------------
alter table usuario        add column if not exists confiabilidade smallint not null default 50;
alter table usuario        add column if not exists aceitou_termos_em timestamptz;
alter table registro_fila  add column if not exists latitude  double precision;
alter table registro_fila  add column if not exists longitude double precision;
alter table relato         add column if not exists autor text;
alter table avaliacao      add column if not exists autor text;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'ck_usuario_confiabilidade') then
        alter table usuario add constraint ck_usuario_confiabilidade check (confiabilidade between 0 and 100);
    end if;
end;
$$;

----------------------------------------------------------------------------------------------
-- 3. Nome público (primeiro nome e inicial do sobrenome): o nome completo nunca sai do banco
----------------------------------------------------------------------------------------------
create or replace function fn_nome_publico(p_nome text) returns text
language plpgsql immutable as $$
declare
    v_partes text[] := regexp_split_to_array(trim(coalesce(p_nome, '')), '\s+');
begin
    if coalesce(v_partes[1], '') = '' then
        return 'Cidadão';
    end if;
    if array_length(v_partes, 1) = 1 then
        return v_partes[1];
    end if;
    return v_partes[1] || ' ' || upper(left(v_partes[array_length(v_partes, 1)], 1)) || '.';
end;
$$;

create or replace function trg_fn_preencher_autor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    new.autor := fn_nome_publico((select nome from usuario where id = new.usuario_id));
    return new;
end;
$$;

drop trigger if exists trg_relato_autor on relato;
create trigger trg_relato_autor before insert on relato
for each row execute function trg_fn_preencher_autor();

drop trigger if exists trg_avaliacao_autor on avaliacao;
create trigger trg_avaliacao_autor before insert or update of usuario_id on avaliacao
for each row execute function trg_fn_preencher_autor();

update relato r set autor = fn_nome_publico(u.nome) from usuario u where u.id = r.usuario_id and r.autor is null;
update avaliacao a set autor = fn_nome_publico(u.nome) from usuario u where u.id = a.usuario_id and a.autor is null;

create or replace view vw_ranking_colaboradores as
select row_number() over (order by us.pontos desc, us.criado_em) as posicao,
       us.id as usuario_id, fn_nome_publico(us.nome) as nome, us.pontos, us.nivel,
       (select count(*) from registro_fila r where r.usuario_id = us.id) as total_registros
  from usuario us
 where us.pontos > 0;

----------------------------------------------------------------------------------------------
-- 4. Confiabilidade: quanto a percepção de fila do usuário concorda com a espera que ele mediu
----------------------------------------------------------------------------------------------
create or replace function fn_tamanho_por_minutos(p_minutos integer) returns text
language plpgsql immutable as $$
begin
    if p_minutos is null then return null; end if;
    if p_minutos <= 5 then return 'sem_fila'; end if;
    if p_minutos <= 25 then return 'curta'; end if;
    if p_minutos <= 60 then return 'media'; end if;
    if p_minutos <= 110 then return 'longa'; end if;
    return 'lotada';
end;
$$;

create or replace function fn_indice_tamanho(p_tamanho text) returns integer
language sql immutable as $$
    select case p_tamanho when 'sem_fila' then 0 when 'curta' then 1 when 'media' then 2
                          when 'longa' then 3 when 'lotada' then 4 end;
$$;

-- Peso do registro: nível de reputação vezes um fator da confiabilidade (0,5 a 1,5).
create or replace function fn_peso_usuario(p_usuario_id uuid) returns numeric
language plpgsql stable as $$
declare
    v_nivel text;
    v_conf  integer;
    v_base  numeric;
begin
    select nivel, confiabilidade into v_nivel, v_conf from usuario where id = p_usuario_id;
    v_base := case v_nivel when 'confiavel' then 2.0 when 'colaborador' then 1.5 else 1.0 end;
    return round(v_base * (0.5 + coalesce(v_conf, 50) / 100.0), 1);
end;
$$;

create or replace function trg_fn_registro_confiabilidade() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_distancia integer;
    v_delta     integer;
begin
    if new.tipo <> 'checkin' or new.espera_real_min is null
       or old.espera_real_min is not null then
        return null;
    end if;

    v_distancia := abs(fn_indice_tamanho(new.tamanho_fila)
                       - fn_indice_tamanho(fn_tamanho_por_minutos(new.espera_real_min)));
    v_delta := case when v_distancia = 0 then 2 when v_distancia = 1 then 0 else -4 end;

    update usuario
       set confiabilidade = greatest(0, least(100, confiabilidade + v_delta))
     where id = new.usuario_id;
    return null;
end;
$$;

drop trigger if exists trg_registro_confiabilidade on registro_fila;
-- Dispara na coluna que o app atualiza (atendido_em); a espera medida é calculada por outro gatilho antes.
create trigger trg_registro_confiabilidade
after update of atendido_em on registro_fila
for each row execute function trg_fn_registro_confiabilidade();

----------------------------------------------------------------------------------------------
-- 5. Registro de fila: limite por hora e validação de localização (opcional, por configuração)
----------------------------------------------------------------------------------------------
create or replace function trg_fn_registro_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_raio_km   double precision;
    v_distancia double precision;
    v_unidade   unidade%rowtype;
begin
    if fn_chamada_do_app() then
        if (select count(*) from registro_fila
             where usuario_id = new.usuario_id
               and chegada_em > now() - interval '1 hour') >= fn_config('max_registros_hora', '12')::integer then
            raise exception 'Muitos registros em pouco tempo. Tente de novo mais tarde.' using errcode = 'PR007';
        end if;

        if fn_config('validar_localizacao', 'false') = 'true' then
            if new.latitude is null or new.longitude is null then
                raise exception 'Ative a localização do aparelho para informar a fila.' using errcode = 'PR006';
            end if;
            select * into v_unidade from unidade where id = new.unidade_id;
            v_raio_km := fn_config('raio_validacao_km', '0.5')::double precision;
            v_distancia := fn_distancia_km(new.latitude, new.longitude, v_unidade.latitude, v_unidade.longitude);
            if v_distancia > v_raio_km then
                raise exception 'Você precisa estar perto da unidade para informar a fila (a menos de % m).',
                    round(v_raio_km * 1000) using errcode = 'PR006';
            end if;
        end if;
    end if;

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
        new.status := 'concluido';
    else
        update registro_fila
           set status = 'desistiu', saida_em = new.chegada_em
         where usuario_id = new.usuario_id
           and status = 'aguardando'
           and chegada_em <= new.chegada_em;
    end if;

    return new;
end;
$$;

----------------------------------------------------------------------------------------------
-- 6. Avisos: limite por hora e sem repetir o mesmo aviso na mesma unidade em 30 minutos
----------------------------------------------------------------------------------------------
create or replace function trg_fn_relato_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if fn_chamada_do_app() then
        if (select count(*) from relato
             where usuario_id = new.usuario_id
               and criado_em > now() - interval '1 hour') >= fn_config('max_relatos_hora', '3')::integer then
            raise exception 'Você já publicou muitos avisos na última hora. Tente de novo mais tarde.'
                using errcode = 'PR008';
        end if;

        if exists (select 1 from relato
                    where usuario_id = new.usuario_id and unidade_id = new.unidade_id
                      and tipo = new.tipo and criado_em > now() - interval '30 minutes') then
            raise exception 'Você já publicou este aviso nesta unidade há pouco.' using errcode = 'PR008';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_relato_antes_inserir on relato;
create trigger trg_relato_antes_inserir before insert on relato
for each row execute function trg_fn_relato_antes_inserir();

----------------------------------------------------------------------------------------------
-- 7. LGPD: exclusão de conta pelo próprio usuário
----------------------------------------------------------------------------------------------
create or replace function excluir_minha_conta() returns void
language plpgsql security definer set search_path = public as $$
declare
    v_id uuid;
begin
    if to_regprocedure('auth.uid()') is not null then
        execute 'select auth.uid()' into v_id;
    else
        v_id := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    end if;

    if v_id is null then
        raise exception 'É preciso entrar para excluir a conta.' using errcode = 'PR009';
    end if;

    -- As tabelas filhas (registros, avisos, avaliações, favoritos, alertas e pontos) caem em cascata.
    delete from usuario where id = v_id;

    if to_regclass('auth.users') is not null then
        execute 'delete from auth.users where id = $1' using v_id;
    end if;
end;
$$;

----------------------------------------------------------------------------------------------
-- 8. Somente no Supabase: permissões, segurança por linha e cadastro com consentimento
----------------------------------------------------------------------------------------------
do $$
begin
    if to_regnamespace('auth') is null then
        raise notice 'Schema auth não encontrado: pulando a parte do Supabase.';
        return;
    end if;

    -- Tabela de configuração nunca é exposta ao app.
    alter table configuracao enable row level security;
    revoke all on configuracao from anon, authenticated;

    -- Perfil completo (nome, pontos, confiabilidade) só para o próprio usuário.
    drop policy if exists leitura_publica on usuario;
    drop policy if exists perfil_proprio_leitura on usuario;
    create policy perfil_proprio_leitura on usuario for select to authenticated using (id = auth.uid());
    revoke select on usuario from anon;

    -- Coordenadas informadas pelo aplicativo no momento do registro.
    grant insert (latitude, longitude) on registro_fila to authenticated;

    -- Exclusão de conta: só quem está autenticado.
    revoke execute on function excluir_minha_conta() from public, anon;
    grant execute on function excluir_minha_conta() to authenticated;
    revoke execute on function fn_config(text, text) from public, anon, authenticated;

    -- Cadastro: cria o perfil guardando a data do aceite dos termos enviada pelo app.
    create or replace function trg_fn_novo_usuario_auth() returns trigger
    language plpgsql security definer set search_path = public as $f$
    begin
        insert into usuario (id, nome, aceitou_termos_em)
        values (new.id,
                coalesce(nullif(new.raw_user_meta_data ->> 'nome', ''), 'Cidadão'),
                case when (new.raw_user_meta_data ->> 'aceitou_termos') = 'true' then now() end)
        on conflict (id) do nothing;
        return new;
    end;
    $f$;
end;
$$;

-- ===== 13_sugestao_correcao.sql =====
-- Passa Rápido: sugestões de correção dos dados das unidades (edição colaborativa com análise).
-- O cadastro vem do CNES e do OpenStreetMap e tem erros (coordenada no lugar errado, telefone antigo, unidade fechada).
-- Quem usa o app pode avisar; a sugestão fica PENDENTE até alguém analisar com prc_analisar_sugestao.
-- Idempotente: pode ser executado mais de uma vez. Aplique depois dos scripts 01 a 09.

create table if not exists sugestao_correcao (
    id           bigint generated always as identity primary key,
    unidade_id   bigint not null references unidade (id) on delete cascade,
    usuario_id   uuid   not null references usuario (id) on delete cascade,
    campo        text   not null
                 check (campo in ('localizacao', 'telefone', 'endereco', 'nome', 'fechada', 'outro')),
    descricao    text   not null check (char_length(btrim(descricao)) between 5 and 500),
    latitude     double precision check (latitude between -90 and 90),
    longitude    double precision check (longitude between -180 and 180),
    status       text   not null default 'pendente' check (status in ('pendente', 'aceita', 'recusada')),
    criado_em    timestamptz not null default now(),
    analisado_em timestamptz
);
create index if not exists idx_sugestao_status  on sugestao_correcao (status, criado_em);
create index if not exists idx_sugestao_unidade on sugestao_correcao (unidade_id);

-- A aceitação de uma sugestão rende pontos ao autor.
alter table movimento_pontos drop constraint if exists movimento_pontos_motivo_check;
alter table movimento_pontos add constraint movimento_pontos_motivo_check
    check (motivo in ('checkin', 'observacao', 'atendimento_confirmado', 'relato',
                      'relato_confirmado', 'avaliacao', 'sugestao_aceita'));

----------------------------------------------------------------------------------------------
-- Regras de entrada: limite por hora e sem repetir a mesma sugestão pendente
----------------------------------------------------------------------------------------------
create or replace function trg_fn_sugestao_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if fn_chamada_do_app() then
        if (select count(*) from sugestao_correcao
             where usuario_id = new.usuario_id
               and criado_em > now() - interval '1 hour') >= fn_config('max_sugestoes_hora', '5')::integer then
            raise exception 'Você enviou muitas sugestões na última hora. Tente de novo mais tarde.'
                using errcode = 'PR010';
        end if;

        if exists (select 1 from sugestao_correcao
                    where usuario_id = new.usuario_id and unidade_id = new.unidade_id
                      and campo = new.campo and status = 'pendente') then
            raise exception 'Você já tem uma sugestão em análise para este item desta unidade.'
                using errcode = 'PR010';
        end if;
    end if;
    new.status := 'pendente';
    new.analisado_em := null;
    return new;
end;
$$;

drop trigger if exists trg_sugestao_antes_inserir on sugestao_correcao;
create trigger trg_sugestao_antes_inserir before insert on sugestao_correcao
for each row execute function trg_fn_sugestao_antes_inserir();

----------------------------------------------------------------------------------------------
-- Análise: aceita (aplica a correção e dá pontos ao autor) ou recusa
----------------------------------------------------------------------------------------------
create or replace procedure prc_analisar_sugestao(p_id bigint, p_aceitar boolean)
language plpgsql security definer set search_path = public as $$
declare
    v_sugestao sugestao_correcao%rowtype;
begin
    select * into v_sugestao from sugestao_correcao where id = p_id for update;
    if not found then
        raise exception 'Sugestão % não existe.', p_id using errcode = 'PR011';
    end if;
    if v_sugestao.status <> 'pendente' then
        raise exception 'Sugestão % já foi analisada (%).', p_id, v_sugestao.status using errcode = 'PR011';
    end if;

    if p_aceitar then
        case v_sugestao.campo
            when 'localizacao' then
                if v_sugestao.latitude is not null and v_sugestao.longitude is not null then
                    update unidade set latitude = v_sugestao.latitude, longitude = v_sugestao.longitude
                     where id = v_sugestao.unidade_id;
                end if;
            when 'telefone' then
                update unidade set telefone = btrim(v_sugestao.descricao) where id = v_sugestao.unidade_id;
            when 'endereco' then
                update unidade set endereco = btrim(v_sugestao.descricao) where id = v_sugestao.unidade_id;
            when 'nome' then
                update unidade set nome = btrim(v_sugestao.descricao) where id = v_sugestao.unidade_id;
            when 'fechada' then
                update unidade set ativo = false where id = v_sugestao.unidade_id;
            else
                null; -- "outro": só registra; a correção é feita à mão
        end case;

        insert into movimento_pontos (usuario_id, pontos, motivo)
        values (v_sugestao.usuario_id, 10, 'sugestao_aceita');
    end if;

    update sugestao_correcao
       set status = case when p_aceitar then 'aceita' else 'recusada' end,
           analisado_em = now()
     where id = p_id;
end;
$$;

-- Indicador para a gestão: sugestões por situação e por tipo de problema.
create or replace view vw_sugestoes_resumo as
select campo, status, count(*) as quantidade,
       min(criado_em) filter (where status = 'pendente') as pendente_mais_antiga
  from sugestao_correcao
 group by campo, status;

----------------------------------------------------------------------------------------------
-- Somente no Supabase: segurança por linha e permissões
----------------------------------------------------------------------------------------------
do $$
begin
    revoke execute on procedure prc_analisar_sugestao(bigint, boolean) from public;
    if to_regnamespace('auth') is null then
        raise notice 'Schema auth não encontrado: pulando a parte do Supabase.';
        return;
    end if;

    alter table sugestao_correcao alter column usuario_id set default auth.uid();
    alter table sugestao_correcao enable row level security;
    drop policy if exists sugestao_insercao on sugestao_correcao;
    drop policy if exists sugestao_leitura on sugestao_correcao;
    create policy sugestao_insercao on sugestao_correcao for insert to authenticated
        with check (usuario_id = auth.uid());
    create policy sugestao_leitura on sugestao_correcao for select to authenticated
        using (usuario_id = auth.uid());

    revoke all on sugestao_correcao from anon, authenticated;
    grant select on sugestao_correcao to authenticated;
    grant insert (unidade_id, campo, descricao, latitude, longitude) on sugestao_correcao to authenticated;

    revoke all on vw_sugestoes_resumo from anon, authenticated;
    revoke execute on procedure prc_analisar_sugestao(bigint, boolean) from anon, authenticated;
end;
$$;

-- ===== 14_melhorias_publicas.sql =====
-- Passa Rápido: melhorias para o serviço público (idempotente; pode ser executado mais de uma vez).
-- Aplique depois dos scripts 01 a 13. As partes do Supabase só rodam se o schema "auth" existir.
--
--   1. fonte "oficial": leitura de espera enviada por órgão conveniado (só o servidor grava)
--   2. acessibilidade física confirmada pelos usuários (votos)
--   3. denúncia de aviso e de avaliação, com ocultação automática
--   4. moderação: quem é moderador e as rotinas que só ele pode chamar
--   5. consenso: correção de localização aplicada quando várias pessoas confiáveis concordam
--   6. impacto do colaborador na semana
--   7. visão agregada por região para a gestão (sem dado pessoal)

----------------------------------------------------------------------------------------------
-- 0. Apoio
----------------------------------------------------------------------------------------------
-- Usuário da chamada (auth.uid() no Supabase; nulo no banco local, onde não há schema auth).
create or replace function fn_usuario_atual() returns uuid
language plpgsql stable as $$
declare
    v_id uuid;
begin
    if to_regprocedure('auth.uid()') is not null then
        execute 'select auth.uid()' into v_id;
    else
        v_id := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    end if;
    return v_id;
end;
$$;

insert into configuracao (chave, valor, descricao) values
    ('validade_oficial_min', '30',
     'Minutos em que uma leitura oficial de espera vale; depois disso volta a valer a percepção dos cidadãos.'),
    ('max_votos_acessibilidade_hora', '30',
     'Máximo de votos de acessibilidade por usuário a cada hora.'),
    ('max_denuncias_hora', '10',
     'Máximo de denúncias por usuário a cada hora.'),
    ('denuncias_peso_minimo', '3',
     'Soma dos pesos (fn_peso_usuario) das pessoas distintas que denunciaram para o conteúdo ser ocultado.'),
    ('consenso_minimo', '3',
     'Pessoas distintas que precisam sugerir o mesmo ponto para a localização ser corrigida sem moderador.'),
    ('consenso_peso_minimo', '3',
     'Soma dos pesos (fn_peso_usuario) dessas pessoas.'),
    ('consenso_raio_ponto_m', '40',
     'Distância máxima, em metros, entre as sugestões para contarem como o mesmo ponto.'),
    ('consenso_raio_max_km', '5',
     'Maior deslocamento da unidade aplicado por consenso; acima disso a sugestão espera um moderador.')
on conflict (chave) do nothing;

----------------------------------------------------------------------------------------------
-- 1. Fonte oficial de espera (convênio com prefeituras e órgãos)
----------------------------------------------------------------------------------------------
alter table situacao_unidade drop constraint if exists situacao_unidade_fonte_check;
alter table situacao_unidade add constraint situacao_unidade_fonte_check
    check (fonte in ('sem_dados', 'tempo_real', 'historico', 'oficial'));

create table if not exists espera_oficial (
    id            bigint generated always as identity primary key,
    unidade_id    bigint not null references unidade (id) on delete cascade,
    espera_min    integer not null check (espera_min between 0 and 600),
    origem        text not null check (char_length(btrim(origem)) between 2 and 80),
    registrado_em timestamptz not null default now()
);
create index if not exists idx_espera_oficial_unidade on espera_oficial (unidade_id, registrado_em desc);

-- Quem integra (chave de serviço do órgão) chama esta rotina; o app nunca a enxerga.
create or replace procedure prc_registrar_espera_oficial(
    p_unidade_id bigint,
    p_espera_min integer,
    p_origem     text,
    p_em         timestamptz default now()
)
language plpgsql security definer set search_path = public as $$
begin
    if not exists (select 1 from unidade where id = p_unidade_id and ativo) then
        raise exception 'Unidade % não existe ou está inativa.', p_unidade_id using errcode = 'PR012';
    end if;
    if p_em > now() + interval '5 minutes' then
        raise exception 'A leitura não pode estar no futuro.' using errcode = 'PR012';
    end if;
    insert into espera_oficial (unidade_id, espera_min, origem, registrado_em)
    values (p_unidade_id, p_espera_min, p_origem, p_em);
    call prc_recalcular_situacao(p_unidade_id, greatest(p_em, now() - interval '1 minute'));
end;
$$;

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
    v_oficial     integer;
    v_oficial_em  timestamptz;
    v_atualizado  timestamptz;
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

    -- Leitura oficial (convênio com o órgão) recente vale mais que a percepção dos cidadãos.
    select e.espera_min, e.registrado_em into v_oficial, v_oficial_em
      from espera_oficial e
     where e.unidade_id = p_unidade_id
       and e.registrado_em <= p_agora
       and e.registrado_em > p_agora - make_interval(mins => fn_config('validade_oficial_min', '30')::integer)
     order by e.registrado_em desc
     limit 1;

    if v_oficial is not null then
        v_espera     := v_oficial;
        v_fonte      := 'oficial';
        v_confianca  := 95;
        v_atualizado := v_oficial_em;
    elsif coalesce(v_qtd, 0) > 0 then
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
         v_aguardando, coalesce(v_qtd, 0), coalesce(v_atualizado, p_agora))
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
-- Alerta de fila baixa e painel passam a contar a fonte oficial também.
create or replace function trg_fn_situacao_alerta_favoritos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_nome text;
begin
    if new.fonte not in ('tempo_real', 'oficial') or new.espera_estimada_min is null then
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
                or old.fonte not in ('tempo_real', 'oficial')
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
           (select count(*) from situacao_unidade where fonte in ('tempo_real', 'oficial')),
           (select count(*) from registro_fila
             where (chegada_em at time zone 'America/Sao_Paulo')::date
                 = (now() at time zone 'America/Sao_Paulo')::date),
           (select round(avg(espera_estimada_min))::integer
              from situacao_unidade where fonte in ('tempo_real', 'oficial')),
           (select count(distinct usuario_id) from registro_fila
             where chegada_em > now() - interval '7 days');
end;
$$;

-- Porta de entrada para o órgão conveniado: o PostgREST só expõe funções, então a integração chama estas
-- (POST /rest/v1/rpc/...) com a chave de serviço do Supabase. O app e o visitante não têm permissão.
create or replace function fn_registrar_espera_oficial(
    p_unidade_id bigint, p_espera_min integer, p_origem text, p_em timestamptz default now()
) returns void
language plpgsql security definer set search_path = public as $$
begin
    call prc_registrar_espera_oficial(p_unidade_id, p_espera_min, p_origem, p_em);
end;
$$;

-- Lote: [{"unidade_id": 12, "espera_min": 35, "origem": "SMS Prefeitura X", "em": "2026-11-16T10:00:00Z"}, ...]
-- No máximo 500 leituras por chamada; a primeira inválida cancela o lote inteiro.
create or replace function fn_registrar_esperas_oficiais(p_leituras jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare
    v_item jsonb;
    v_n    integer := 0;
begin
    if jsonb_typeof(p_leituras) <> 'array' then
        raise exception 'Envie uma lista de leituras.' using errcode = 'PR012';
    end if;
    if jsonb_array_length(p_leituras) > 500 then
        raise exception 'No máximo 500 leituras por chamada.' using errcode = 'PR012';
    end if;
    for v_item in select * from jsonb_array_elements(p_leituras) loop
        call prc_registrar_espera_oficial(
            (v_item ->> 'unidade_id')::bigint,
            (v_item ->> 'espera_min')::integer,
            v_item ->> 'origem',
            coalesce((v_item ->> 'em')::timestamptz, now()));
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

----------------------------------------------------------------------------------------------
-- 2. Acessibilidade física confirmada pelos usuários
----------------------------------------------------------------------------------------------
create table if not exists acessibilidade_voto (
    unidade_id    bigint not null references unidade (id) on delete cascade,
    usuario_id    uuid   not null references usuario (id) on delete cascade,
    recurso       text   not null check (recurso in ('rampa', 'elevador', 'banheiro_adaptado', 'piso_tatil',
                                                      'libras', 'fila_preferencial', 'vaga_pcd')),
    existe        boolean not null,
    atualizado_em timestamptz not null default now(),
    primary key (unidade_id, usuario_id, recurso)
);

create or replace function trg_fn_acessibilidade_voto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    new.atualizado_em := now();
    if fn_chamada_do_app() and (tg_op = 'INSERT' or new.existe is distinct from old.existe) then
        if (select count(*) from acessibilidade_voto
             where usuario_id = new.usuario_id
               and atualizado_em > now() - interval '1 hour') >= fn_config('max_votos_acessibilidade_hora', '30')::integer then
            raise exception 'Você enviou muitos votos na última hora. Tente de novo mais tarde.'
                using errcode = 'PR013';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_acessibilidade_voto on acessibilidade_voto;
create trigger trg_acessibilidade_voto before insert or update on acessibilidade_voto
for each row execute function trg_fn_acessibilidade_voto();

-- Quantas pessoas disseram que o recurso existe e quantas disseram que não. Só números, sem identificar ninguém.
create or replace view vw_acessibilidade_unidade as
select unidade_id, recurso,
       count(*) filter (where existe)     as sim,
       count(*) filter (where not existe) as nao
  from acessibilidade_voto
 group by unidade_id, recurso;

----------------------------------------------------------------------------------------------
-- 3. Denúncia de aviso e de avaliação, com ocultação automática
----------------------------------------------------------------------------------------------
alter table avaliacao add column if not exists oculta boolean not null default false;

-- O texto ocultado sai das tabelas públicas e fica aqui, onde só a moderação enxerga.
create table if not exists conteudo_oculto (
    alvo       text   not null check (alvo in ('relato', 'avaliacao')),
    alvo_id    bigint not null,
    texto      text   not null,
    oculto_em  timestamptz not null default now(),
    primary key (alvo, alvo_id)
);

create table if not exists denuncia (
    id          bigint generated always as identity primary key,
    alvo        text   not null check (alvo in ('relato', 'avaliacao')),
    alvo_id     bigint not null,
    usuario_id  uuid   not null references usuario (id) on delete cascade,
    motivo      text   not null check (motivo in ('falso', 'ofensivo', 'spam', 'outro')),
    resolvida   boolean not null default false,
    criado_em   timestamptz not null default now(),
    unique (alvo, alvo_id, usuario_id)
);
create index if not exists idx_denuncia_alvo on denuncia (alvo, alvo_id);

create or replace function fn_ocultar_conteudo(p_alvo text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
    if p_alvo = 'relato' then
        insert into conteudo_oculto (alvo, alvo_id, texto)
        select 'relato', id, descricao from relato where id = p_id and descricao is not null
        on conflict do nothing;
        update relato set descricao = null, expira_em = least(expira_em, now()) where id = p_id;
    else
        insert into conteudo_oculto (alvo, alvo_id, texto)
        select 'avaliacao', id, comentario from avaliacao where id = p_id and comentario is not null
        on conflict do nothing;
        update avaliacao set comentario = null, oculta = true where id = p_id;
    end if;
end;
$$;

create or replace function trg_fn_denuncia_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_autor uuid;
begin
    new.resolvida := false;
    if new.alvo = 'relato' then
        select usuario_id into v_autor from relato where id = new.alvo_id;
    else
        select usuario_id into v_autor from avaliacao where id = new.alvo_id;
    end if;
    if v_autor is null then
        raise exception 'O conteúdo denunciado não existe mais.' using errcode = 'PR014';
    end if;
    if fn_chamada_do_app() then
        if v_autor = new.usuario_id then
            raise exception 'Você não pode denunciar o seu próprio conteúdo.' using errcode = 'PR014';
        end if;
        if exists (select 1 from denuncia where alvo = new.alvo and alvo_id = new.alvo_id and usuario_id = new.usuario_id) then
            raise exception 'Você já denunciou este conteúdo.' using errcode = 'PR014';
        end if;
        if (select count(*) from denuncia
             where usuario_id = new.usuario_id
               and criado_em > now() - interval '1 hour') >= fn_config('max_denuncias_hora', '10')::integer then
            raise exception 'Você enviou muitas denúncias na última hora. Tente de novo mais tarde.'
                using errcode = 'PR013';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_denuncia_antes_inserir on denuncia;
create trigger trg_denuncia_antes_inserir before insert on denuncia
for each row execute function trg_fn_denuncia_antes_inserir();

-- Oculta quando a soma dos pesos de quem denunciou chega ao mínimo (pessoas confiáveis pesam mais).
create or replace function trg_fn_denuncia_depois_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_peso numeric;
begin
    select coalesce(sum(fn_peso_usuario(usuario_id)), 0) into v_peso
      from denuncia
     where alvo = new.alvo and alvo_id = new.alvo_id and not resolvida;
    if v_peso >= fn_config('denuncias_peso_minimo', '3')::numeric then
        perform fn_ocultar_conteudo(new.alvo, new.alvo_id);
    end if;
    return null;
end;
$$;

drop trigger if exists trg_denuncia_depois_inserir on denuncia;
create trigger trg_denuncia_depois_inserir after insert on denuncia
for each row execute function trg_fn_denuncia_depois_inserir();

-- O autor não desfaz a ocultação editando a própria avaliação.
-- Sem "security definer" de propósito: current_user é quem está escrevendo (o app) e não o dono da rotina
-- de moderação, que precisa poder ocultar.
create or replace function trg_fn_avaliacao_oculta() returns trigger
language plpgsql set search_path = public as $$
begin
    if current_user in ('anon', 'authenticated') then
        if tg_op = 'INSERT' then
            new.oculta := false;
        else
            new.oculta := old.oculta;
            if old.oculta then new.comentario := null; end if;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_avaliacao_oculta on avaliacao;
create trigger trg_avaliacao_oculta before insert or update on avaliacao
for each row execute function trg_fn_avaliacao_oculta();

----------------------------------------------------------------------------------------------
-- 4. Moderação
----------------------------------------------------------------------------------------------
create table if not exists moderador (
    usuario_id uuid primary key references usuario (id) on delete cascade,
    desde      timestamptz not null default now()
);
-- Para tornar alguém moderador (no SQL Editor, como administrador):
--   insert into moderador (usuario_id) select id from auth.users where email = 'pessoa@exemplo.com';

create or replace function fn_sou_moderador() returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from moderador where usuario_id = fn_usuario_atual());
$$;

create or replace function fn_exigir_moderador() returns void
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_usuario_atual() is null then
        raise exception 'É preciso entrar para acessar a moderação.' using errcode = 'PR009';
    end if;
    if not fn_sou_moderador() then
        raise exception 'Acesso restrito a moderadores.' using errcode = 'PR012';
    end if;
end;
$$;

create or replace function fn_listar_sugestoes_pendentes()
returns table (
    id bigint, unidade_id bigint, unidade_nome text, unidade_endereco text,
    unidade_latitude double precision, unidade_longitude double precision,
    campo text, descricao text, latitude double precision, longitude double precision,
    autor text, apoios bigint, criado_em timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
    perform fn_exigir_moderador();
    return query
    select s.id, s.unidade_id, u.nome, u.endereco, u.latitude, u.longitude,
           s.campo, s.descricao, s.latitude, s.longitude,
           fn_nome_publico(us.nome),
           (select count(*) from sugestao_correcao o
             where o.unidade_id = s.unidade_id and o.campo = s.campo and o.status = 'pendente' and o.id <> s.id),
           s.criado_em
      from sugestao_correcao s
      join unidade u  on u.id = s.unidade_id
      join usuario us on us.id = s.usuario_id
     where s.status = 'pendente'
     order by s.criado_em
     limit 100;
end;
$$;

create or replace function fn_analisar_sugestao(p_id bigint, p_aceitar boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
    perform fn_exigir_moderador();
    call prc_analisar_sugestao(p_id, p_aceitar);
end;
$$;

create or replace function fn_listar_denuncias_pendentes()
returns table (
    alvo text, alvo_id bigint, unidade_nome text, texto text, denuncias bigint, motivos text, oculto boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
    perform fn_exigir_moderador();
    return query
    select d.alvo, d.alvo_id,
           coalesce(ur.nome, ua.nome),
           coalesce(co.texto, r.descricao, a.comentario, '(sem texto)'),
           count(*),
           string_agg(distinct d.motivo, ', '),
           (co.alvo_id is not null)
      from denuncia d
      left join relato r    on d.alvo = 'relato'    and r.id = d.alvo_id
      left join unidade ur  on ur.id = r.unidade_id
      left join avaliacao a on d.alvo = 'avaliacao' and a.id = d.alvo_id
      left join unidade ua  on ua.id = a.unidade_id
      left join conteudo_oculto co on co.alvo = d.alvo and co.alvo_id = d.alvo_id
     where not d.resolvida
     group by d.alvo, d.alvo_id, ur.nome, ua.nome, co.texto, r.descricao, a.comentario, co.alvo_id
     order by count(*) desc
     limit 100;
end;
$$;

-- Moderador decide: manter oculto (a denúncia é encerrada) ou restaurar o texto.
create or replace function fn_resolver_denuncia(p_alvo text, p_alvo_id bigint, p_restaurar boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
    v_texto text;
begin
    perform fn_exigir_moderador();
    if p_restaurar then
        select texto into v_texto from conteudo_oculto where alvo = p_alvo and alvo_id = p_alvo_id;
        if p_alvo = 'relato' then
            update relato set descricao = coalesce(v_texto, descricao),
                              expira_em = greatest(expira_em, now() + interval '1 hour')
             where id = p_alvo_id;
        else
            update avaliacao set comentario = coalesce(v_texto, comentario), oculta = false where id = p_alvo_id;
        end if;
        delete from conteudo_oculto where alvo = p_alvo and alvo_id = p_alvo_id;
    else
        perform fn_ocultar_conteudo(p_alvo, p_alvo_id);
    end if;
    update denuncia set resolvida = true where alvo = p_alvo and alvo_id = p_alvo_id;
end;
$$;

----------------------------------------------------------------------------------------------
-- 5. Consenso: várias pessoas confiáveis sugerindo o mesmo ponto corrigem a localização sem moderador
----------------------------------------------------------------------------------------------
create or replace function trg_fn_sugestao_consenso() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_minimo   integer := fn_config('consenso_minimo', '3')::integer;
    v_peso_min numeric := fn_config('consenso_peso_minimo', '3')::numeric;
    v_raio_m   double precision := fn_config('consenso_raio_ponto_m', '40')::double precision;
    v_max_km   double precision := fn_config('consenso_raio_max_km', '5')::double precision;
    v_ids      bigint[];
    v_pessoas  integer;
    v_lat      double precision;
    v_lon      double precision;
    v_peso     numeric;
    v_unidade  unidade%rowtype;
begin
    if new.campo <> 'localizacao' or new.latitude is null or new.longitude is null then
        return null;
    end if;

    select array_agg(s.id), count(distinct s.usuario_id), avg(s.latitude), avg(s.longitude)
      into v_ids, v_pessoas, v_lat, v_lon
      from sugestao_correcao s
     where s.unidade_id = new.unidade_id and s.campo = 'localizacao' and s.status = 'pendente'
       and s.latitude is not null and s.longitude is not null
       and fn_distancia_km(new.latitude, new.longitude, s.latitude, s.longitude) * 1000 <= v_raio_m;

    if coalesce(v_pessoas, 0) < v_minimo then return null; end if;

    select coalesce(sum(fn_peso_usuario(p.usuario_id)), 0) into v_peso
      from (select distinct usuario_id from sugestao_correcao where id = any (v_ids)) p;
    if v_peso < v_peso_min then return null; end if;

    select * into v_unidade from unidade where id = new.unidade_id;
    if fn_distancia_km(v_unidade.latitude, v_unidade.longitude, v_lat, v_lon) > v_max_km then
        return null; -- mudança grande demais: espera um moderador
    end if;

    update unidade set latitude = v_lat, longitude = v_lon where id = new.unidade_id;
    insert into movimento_pontos (usuario_id, pontos, motivo)
    select distinct usuario_id, 10, 'sugestao_aceita' from sugestao_correcao where id = any (v_ids);
    update sugestao_correcao set status = 'aceita', analisado_em = now() where id = any (v_ids);
    return null;
end;
$$;

drop trigger if exists trg_sugestao_consenso on sugestao_correcao;
create trigger trg_sugestao_consenso after insert on sugestao_correcao
for each row execute function trg_fn_sugestao_consenso();

-- Sugestão de horário de funcionamento: o moderador aplica à mão (o texto é livre).
alter table sugestao_correcao drop constraint if exists sugestao_correcao_campo_check;
alter table sugestao_correcao add constraint sugestao_correcao_campo_check
    check (campo in ('localizacao', 'telefone', 'endereco', 'nome', 'fechada', 'horario', 'outro'));

----------------------------------------------------------------------------------------------
-- 6. Impacto do colaborador nos últimos 7 dias (só números dele mesmo)
----------------------------------------------------------------------------------------------
create or replace function fn_meu_impacto()
returns table (
    registros_7d bigint, unidades_7d bigint, pontos_7d bigint,
    avisos_7d bigint, avaliacoes_7d bigint, sugestoes_aceitas bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
    v_id uuid := fn_usuario_atual();
begin
    if v_id is null then
        raise exception 'É preciso entrar para ver o seu impacto.' using errcode = 'PR009';
    end if;
    return query
    select (select count(*) from registro_fila where usuario_id = v_id and chegada_em > now() - interval '7 days'),
           (select count(distinct unidade_id) from registro_fila where usuario_id = v_id and chegada_em > now() - interval '7 days'),
           (select coalesce(sum(pontos), 0) from movimento_pontos where usuario_id = v_id and criado_em > now() - interval '7 days'),
           (select count(*) from relato where usuario_id = v_id and criado_em > now() - interval '7 days'),
           (select count(*) from avaliacao where usuario_id = v_id and criado_em > now() - interval '7 days'),
           (select count(*) from sugestao_correcao where usuario_id = v_id and status = 'aceita');
end;
$$;

----------------------------------------------------------------------------------------------
-- 7. Visão agregada por região para a gestão (nenhum dado pessoal)
----------------------------------------------------------------------------------------------
create or replace view vw_gestao_regiao as
with base as (
    select u.id, u.cidade,
           coalesce(nullif(btrim(u.bairro), ''), 'Bairro não informado') as bairro,
           t.nome as tipo, s.espera_estimada_min, coalesce(s.fonte, 'sem_dados') as fonte,
           fn_unidade_aberta(u.id) as aberta
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      left join situacao_unidade s on s.unidade_id = u.id
     where u.ativo
),
picos as (
    select b.cidade, b.bairro, b.tipo, h.hora, round(avg(h.media_espera_min))::integer as media,
           row_number() over (partition by b.cidade, b.bairro, b.tipo
                              order by avg(h.media_espera_min) desc, h.hora) as ordem
      from base b
      join historico_espera h on h.unidade_id = b.id
     group by b.cidade, b.bairro, b.tipo, h.hora
),
registros as (
    select b.cidade, b.bairro, b.tipo, count(r.id) as total
      from base b
      left join registro_fila r on r.unidade_id = b.id and r.chegada_em > now() - interval '7 days'
     group by b.cidade, b.bairro, b.tipo
)
select b.cidade, b.bairro, b.tipo,
       count(*)                                                           as unidades,
       count(*) filter (where b.aberta)                                   as abertas_agora,
       round(avg(b.espera_estimada_min) filter (where b.aberta))::integer as espera_media_min,
       count(*) filter (where b.fonte in ('tempo_real', 'oficial'))       as unidades_com_fila_real,
       max(rg.total)                                                      as registros_7d,
       max(p.hora)                                                        as hora_pico,
       max(p.media)                                                       as espera_pico_min
  from base b
  join registros rg on rg.cidade = b.cidade and rg.bairro = b.bairro and rg.tipo = b.tipo
  left join picos p on p.cidade = b.cidade and p.bairro = b.bairro and p.tipo = b.tipo and p.ordem = 1
 group by b.cidade, b.bairro, b.tipo;

----------------------------------------------------------------------------------------------
-- 8. Visões públicas de avisos e avaliações: o identificador do autor não sai do servidor
----------------------------------------------------------------------------------------------
-- Antes, qualquer pessoa lia relato.usuario_id e avaliacao.usuario_id. Com o identificador estável era possível
-- seguir uma pessoa por várias unidades de saúde. Agora o app lê estas visões, que dizem só "é meu ou não".
create or replace view vw_relato_publico as
select r.id, r.unidade_id, r.tipo, r.descricao, r.confirmacoes, r.criado_em, r.expira_em, r.autor,
       coalesce(r.usuario_id = fn_usuario_atual(), false) as proprio
  from relato r;

create or replace view vw_avaliacao_publica as
select a.id, a.unidade_id, a.nota, a.comentario, a.oculta, a.autor, a.criado_em,
       coalesce(a.usuario_id = fn_usuario_atual(), false) as proprio
  from avaliacao a;

----------------------------------------------------------------------------------------------
-- 9. Permissões e segurança por linha (valem no Supabase; o banco local puro não tem esses papéis)
----------------------------------------------------------------------------------------------
-- Rotinas internas: ninguém além do dono as chama.
revoke execute on procedure prc_registrar_espera_oficial(bigint, integer, text, timestamptz) from public;
revoke execute on function fn_ocultar_conteudo(text, bigint) from public;
revoke execute on function fn_exigir_moderador() from public;
revoke execute on function fn_resumo_dados_reais() from public;
revoke execute on function fn_registrar_espera_oficial(bigint, integer, text, timestamptz) from public;
revoke execute on function fn_registrar_esperas_oficiais(jsonb) from public;
revoke execute on function fn_sou_moderador() from public;
revoke execute on function fn_listar_sugestoes_pendentes() from public;
revoke execute on function fn_analisar_sugestao(bigint, boolean) from public;
revoke execute on function fn_listar_denuncias_pendentes() from public;
revoke execute on function fn_resolver_denuncia(text, bigint, boolean) from public;
revoke execute on function fn_meu_impacto() from public;

do $$
declare
    r record;
begin
    if to_regnamespace('auth') is null then
        raise notice 'Schema auth não encontrado: pulando a parte do Supabase.';
        return;
    end if;

    -- Funções de gatilho nunca são chamadas pelo app (o gatilho dispara sem precisar desta permissão).
    for r in select p.oid::regprocedure as f
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.prorettype = 'trigger'::regtype loop
        execute format('revoke execute on function %s from public, anon, authenticated', r.f);
    end loop;

    revoke execute on procedure prc_registrar_espera_oficial(bigint, integer, text, timestamptz) from anon, authenticated;
    revoke execute on function fn_registrar_espera_oficial(bigint, integer, text, timestamptz) from anon, authenticated;
    revoke execute on function fn_registrar_esperas_oficiais(jsonb) from anon, authenticated;
    grant execute on function fn_registrar_espera_oficial(bigint, integer, text, timestamptz) to service_role;
    grant execute on function fn_registrar_esperas_oficiais(jsonb) to service_role;
    revoke execute on function fn_ocultar_conteudo(text, bigint) from anon, authenticated;
    revoke execute on function fn_exigir_moderador() from anon, authenticated;
    -- fn_usuario_atual() fica liberada de propósito: as visões públicas a chamam com a permissão de quem consulta, e ela só devolve o próprio identificador.
    revoke execute on function fn_resumo_dados_reais() from anon, authenticated;
    revoke execute on function confirmar_relato(bigint) from public, anon;
    grant execute on function confirmar_relato(bigint) to authenticated;

    -- Rotinas do app: só quem entrou.
    revoke execute on function fn_sou_moderador() from anon;
    revoke execute on function fn_listar_sugestoes_pendentes() from anon;
    revoke execute on function fn_analisar_sugestao(bigint, boolean) from anon;
    revoke execute on function fn_listar_denuncias_pendentes() from anon;
    revoke execute on function fn_resolver_denuncia(text, bigint, boolean) from anon;
    revoke execute on function fn_meu_impacto() from anon;
    grant execute on function fn_sou_moderador() to authenticated;
    grant execute on function fn_listar_sugestoes_pendentes() to authenticated;
    grant execute on function fn_analisar_sugestao(bigint, boolean) to authenticated;
    grant execute on function fn_listar_denuncias_pendentes() to authenticated;
    grant execute on function fn_resolver_denuncia(text, bigint, boolean) to authenticated;
    grant execute on function fn_meu_impacto() to authenticated;

    -- Tabelas que só o servidor e a moderação tocam: sem política e sem permissão para o app.
    alter table espera_oficial  enable row level security;
    alter table conteudo_oculto enable row level security;
    alter table moderador       enable row level security;
    revoke all on espera_oficial, conteudo_oculto, moderador from anon, authenticated;

    -- Acessibilidade: cada pessoa lê e grava só os seus votos; o público lê a contagem pela view.
    alter table acessibilidade_voto alter column usuario_id set default auth.uid();
    alter table acessibilidade_voto enable row level security;
    drop policy if exists voto_proprio on acessibilidade_voto;
    create policy voto_proprio on acessibilidade_voto for all to authenticated
        using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());
    revoke all on acessibilidade_voto from anon, authenticated;
    grant select, insert, update on acessibilidade_voto to authenticated;

    -- Denúncia: só inserir em nome próprio; ninguém lê (a moderação usa as rotinas acima).
    alter table denuncia alter column usuario_id set default auth.uid();
    alter table denuncia enable row level security;
    drop policy if exists denuncia_insercao on denuncia;
    create policy denuncia_insercao on denuncia for insert to authenticated with check (usuario_id = auth.uid());
    revoke all on denuncia from anon, authenticated;
    grant insert (alvo, alvo_id, usuario_id, motivo) on denuncia to authenticated;

    -- Avisos e avaliações: a tabela só é legível pelo próprio autor; o público lê pelas visões acima.
    drop policy if exists leitura_publica on relato;
    drop policy if exists relato_proprio_leitura on relato;
    create policy relato_proprio_leitura on relato for select to authenticated using (usuario_id = auth.uid());
    drop policy if exists leitura_publica on avaliacao;
    drop policy if exists avaliacao_proprio_leitura on avaliacao;
    create policy avaliacao_proprio_leitura on avaliacao for select to authenticated using (usuario_id = auth.uid());
    revoke select on relato, avaliacao from anon;
    grant select on vw_relato_publico, vw_avaliacao_publica, vw_acessibilidade_unidade, vw_gestao_regiao to anon, authenticated;

    -- Endurecimento geral (vale para as tabelas dos scripts anteriores também):
    -- o visitante só lê; ninguém precisa de TRUNCATE, REFERENCES ou TRIGGER pelo app; visões não são gravadas.
    revoke insert, update, delete on all tables in schema public from anon;
    revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
    revoke insert, update, delete on vw_mapa_unidades, vw_indicadores_unidade, vw_ranking_colaboradores,
        vw_gestao_regiao, vw_acessibilidade_unidade, vw_relato_publico, vw_avaliacao_publica from authenticated;
end;
$$;
