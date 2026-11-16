-- Testes das regras de segurança e anti-abuso (script 09).
-- Uso: psql -v ON_ERROR_STOP=1 -d passa_rapido -f tests/test_regras_09.sql
-- Roda dentro de uma transação e desfaz tudo ao final.
begin;

grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

create or replace function pg_temp.confere(p_descricao text, p_condicao boolean) returns void
language plpgsql as $$
begin
    if p_condicao is not true then raise exception 'FALHOU: %', p_descricao; end if;
    raise notice 'ok: %', p_descricao;
end;
$$;
grant execute on function pg_temp.confere(text, boolean) to authenticated;

do $$
declare
    v_unidade  bigint;
    v_outra    bigint;
    v_terceira bigint;
    v_u        uuid := gen_random_uuid();
    v_v        uuid := gen_random_uuid();
    v_reg      bigint;
    v_erro     text;
    v_conf     integer;
    v_lat      double precision;
    v_lng      double precision;
begin
    select id, latitude, longitude into v_unidade, v_lat, v_lng from unidade where ativo order by id limit 1;
    select id into v_outra    from unidade where ativo and id <> v_unidade order by id limit 1;
    select id into v_terceira from unidade where ativo and id not in (v_unidade, v_outra) order by id limit 1;
    insert into usuario (id, nome) values (v_u, 'Ana Maria de Souza'), (v_v, 'Beto');

    -- Nome público
    perform pg_temp.confere('nome público usa primeiro nome e inicial do sobrenome', fn_nome_publico('Ana Maria de Souza') = 'Ana S.');
    perform pg_temp.confere('nome único permanece', fn_nome_publico('Beto') = 'Beto');
    perform pg_temp.confere('nome vazio vira "Cidadão"', fn_nome_publico('   ') = 'Cidadão' and fn_nome_publico(null) = 'Cidadão');

    execute 'set local role authenticated';

    -- Autor denormalizado e ranking sem nome completo
    insert into relato (unidade_id, usuario_id, tipo) values (v_unidade, v_u, 'sem_medico');
    perform pg_temp.confere('aviso guarda só o nome público do autor', (select autor from relato where usuario_id = v_u limit 1) = 'Ana S.');

    -- Limite de avisos por hora (padrão 3) e repetição do mesmo aviso
    begin
        insert into relato (unidade_id, usuario_id, tipo) values (v_unidade, v_u, 'sem_medico');
        v_erro := 'nenhum';
    exception when sqlstate 'PR008' then v_erro := 'PR008'; end;
    perform pg_temp.confere('mesmo aviso na mesma unidade em 30 min é recusado', v_erro = 'PR008');

    insert into relato (unidade_id, usuario_id, tipo) values (v_unidade, v_u, 'sem_vacina');
    insert into relato (unidade_id, usuario_id, tipo) values (v_unidade, v_u, 'sistema_fora');
    begin
        insert into relato (unidade_id, usuario_id, tipo) values (v_outra, v_u, 'sem_senha');
        v_erro := 'nenhum';
    exception when sqlstate 'PR008' then v_erro := 'PR008'; end;
    perform pg_temp.confere('quarto aviso na mesma hora é recusado (limite 3)', v_erro = 'PR008');

    -- Limite de registros por hora
    execute 'reset role';
    update configuracao set valor = '2' where chave = 'max_registros_hora';
    execute 'set local role authenticated';
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_unidade, v_v, 'observacao', 'curta');
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_outra, v_v, 'observacao', 'curta');
    begin
        insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_terceira, v_v, 'observacao', 'curta');
        v_erro := 'nenhum';
    exception when sqlstate 'PR007' then v_erro := 'PR007'; end;
    perform pg_temp.confere('terceiro registro em uma hora é recusado quando o limite é 2', v_erro = 'PR007');
    execute 'reset role';
    update configuracao set valor = '12' where chave = 'max_registros_hora';

    -- Validação de localização (desligada por padrão)
    perform pg_temp.confere('validação de localização começa desligada', fn_config('validar_localizacao') = 'false');
    update configuracao set valor = 'true' where chave = 'validar_localizacao';
    execute 'set local role authenticated';
    begin
        insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_unidade, v_u, 'observacao', 'media');
        v_erro := 'nenhum';
    exception when sqlstate 'PR006' then v_erro := 'PR006'; end;
    perform pg_temp.confere('ligada: sem coordenadas é recusado', v_erro = 'PR006');
    begin
        insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, latitude, longitude)
        values (v_unidade, v_u, 'observacao', 'media', v_lat + 0.5, v_lng + 0.5);
        v_erro := 'nenhum';
    exception when sqlstate 'PR006' then v_erro := 'PR006'; end;
    perform pg_temp.confere('ligada: a 70 km da unidade é recusado', v_erro = 'PR006');
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, latitude, longitude)
    values (v_unidade, v_u, 'observacao', 'media', v_lat + 0.0005, v_lng);
    perform pg_temp.confere('ligada: a cerca de 55 m da unidade é aceito', true);
    execute 'reset role';
    update configuracao set valor = 'false' where chave = 'validar_localizacao';

    -- Rotinas do servidor não passam pela validação de cliente
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_terceira, v_u, 'observacao', 'curta');
    perform pg_temp.confere('chamadas do servidor (sem papel authenticated) não são barradas', true);

    -- Confiabilidade
    update usuario set confiabilidade = 50, nivel = 'iniciante', pontos = 0 where id = v_v;
    perform pg_temp.confere('confiabilidade 50 mantém o peso 1,0 do iniciante', fn_peso_usuario(v_v) = 1.0);
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, chegada_em)
    values (v_outra, v_v, 'checkin', 'lotada', now() - interval '31 minutes') returning id into v_reg;
    update registro_fila set atendido_em = now() - interval '30 minutes' where id = v_reg;
    select confiabilidade into v_conf from usuario where id = v_v;
    perform pg_temp.confere('disse "lotada" e foi atendido em 1 min: confiabilidade cai 4 (50 -> 46)', v_conf = 46);
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, chegada_em)
    values (v_terceira, v_v, 'checkin', 'curta', now() - interval '12 minutes') returning id into v_reg;
    update registro_fila set atendido_em = now() - interval '2 minutes' where id = v_reg;
    select confiabilidade into v_conf from usuario where id = v_v;
    perform pg_temp.confere('disse "curta" e esperou 10 min: confiabilidade sobe 2 (46 -> 48)', v_conf = 48);
    update usuario set confiabilidade = 100, nivel = 'colaborador' where id = v_v;
    perform pg_temp.confere('colaborador com confiabilidade 100 pesa 1,5 x 1,5 = 2,3', fn_peso_usuario(v_v) = 2.3);
    update usuario set confiabilidade = 0, nivel = 'iniciante' where id = v_v;
    perform pg_temp.confere('iniciante com confiabilidade 0 pesa 0,5', fn_peso_usuario(v_v) = 0.5);

    -- Ranking só com nome público
    update usuario set pontos = 500 where id = v_u;
    perform pg_temp.confere('ranking mostra "Ana S." e nunca o nome completo', (select nome from vw_ranking_colaboradores where usuario_id = v_u) = 'Ana S.');

    -- Exclusão de conta
    perform set_config('request.jwt.claim.sub', v_u::text, true);
    perform excluir_minha_conta();
    perform pg_temp.confere('exclusão remove o usuário', not exists (select 1 from usuario where id = v_u));
    perform pg_temp.confere('exclusão leva junto registros, avisos e pontos', not exists (select 1 from relato where usuario_id = v_u) and not exists (select 1 from registro_fila where usuario_id = v_u));
    perform set_config('request.jwt.claim.sub', '', true);
    begin
        perform excluir_minha_conta();
        v_erro := 'nenhum';
    exception when sqlstate 'PR009' then v_erro := 'PR009'; end;
    perform pg_temp.confere('exclusão sem estar autenticado é recusada', v_erro = 'PR009');
end;
$$;

rollback;
