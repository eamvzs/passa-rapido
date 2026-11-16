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
