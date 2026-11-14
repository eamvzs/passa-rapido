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

-- Somente para demonstração: movimento simulado a cada 5 minutos.
-- Para desligar: select cron.unschedule('passa-rapido-simulador');
select cron.schedule('passa-rapido-simulador',  '*/5 * * * *',  'call prc_simular_movimento(4)');
