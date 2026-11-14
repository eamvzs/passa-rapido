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
