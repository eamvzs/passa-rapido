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
