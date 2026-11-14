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
