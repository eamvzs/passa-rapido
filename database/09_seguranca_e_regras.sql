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
