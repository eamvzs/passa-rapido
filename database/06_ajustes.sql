-- Passa Rápido: ajustes sobre a instalação inicial. Cole no SQL Editor do Supabase e clique em Run.
-- 1) Recomendação considera só unidades abertas. 2) Hora do servidor no atendimento e na saída.
-- 3) Simulador de movimento para demonstração, a cada 5 minutos.


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

revoke execute on procedure prc_simular_movimento(integer) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'passa-rapido-simulador';
select cron.schedule('passa-rapido-simulador', '*/5 * * * *', 'call prc_simular_movimento(4)');

call prc_simular_movimento(8);
