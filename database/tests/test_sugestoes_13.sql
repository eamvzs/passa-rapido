-- Testes das sugestões de correção (script 13).
-- Uso: psql -v ON_ERROR_STOP=1 -d passa_rapido -f tests/test_sugestoes_13.sql
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
    v_unidade bigint;
    v_u       uuid := gen_random_uuid();
    v_s1      bigint;
    v_s2      bigint;
    v_s3      bigint;
    v_s4      bigint;
    v_erro    text;
    v_pontos  integer;
    i         integer;
begin
    select id into v_unidade from unidade where ativo order by id limit 1;
    insert into usuario (id, nome) values (v_u, 'Ana Maria de Souza');

    execute 'set local role authenticated';

    -- Entrada: texto curto demais é recusado pela restrição
    begin
        insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'telefone', 'abc');
        v_erro := 'nenhum';
    exception when check_violation then v_erro := 'check'; end;
    perform pg_temp.confere('descrição com menos de 5 caracteres é recusada', v_erro = 'check');

    begin
        insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'cor_da_parede', 'texto valido');
        v_erro := 'nenhum';
    exception when check_violation then v_erro := 'check'; end;
    perform pg_temp.confere('campo desconhecido é recusado', v_erro = 'check');

    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao, latitude, longitude)
    values (v_unidade, v_u, 'localizacao', 'O pino está a 2 km daqui', -23.5, -46.6) returning id into v_s1;
    perform pg_temp.confere('sugestão válida nasce pendente', (select status from sugestao_correcao where id = v_s1) = 'pendente');

    -- Repetição pendente do mesmo item
    begin
        insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'localizacao', 'de novo a mesma coisa');
        v_erro := 'nenhum';
    exception when sqlstate 'PR010' then v_erro := 'PR010'; end;
    perform pg_temp.confere('mesma sugestão pendente na mesma unidade é recusada', v_erro = 'PR010');

    -- Status enviado pelo app é ignorado (o gatilho força pendente)
    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao, status)
    values (v_unidade, v_u, 'telefone', '(11) 5555-1234', 'aceita') returning id into v_s2;
    perform pg_temp.confere('app não consegue criar sugestão já aceita', (select status from sugestao_correcao where id = v_s2) = 'pendente');

    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'endereco', 'Rua Nova, 100 - Centro') returning id into v_s3;
    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'fechada', 'Fechou em outubro') returning id into v_s4;
    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'nome', 'Novo Nome da Unidade');

    -- Limite por hora (padrão 5)
    begin
        insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'outro', 'mais uma sugestão');
        v_erro := 'nenhum';
    exception when sqlstate 'PR010' then v_erro := 'PR010'; end;
    perform pg_temp.confere('a sexta sugestão na mesma hora é recusada', v_erro = 'PR010');

    execute 'reset role';

    -- Análise: aceitar localização aplica a coordenada e dá 10 pontos
    call prc_analisar_sugestao(v_s1, true);
    perform pg_temp.confere('aceitar localização muda a coordenada da unidade',
        (select latitude = -23.5 and longitude = -46.6 from unidade where id = v_unidade));
    perform pg_temp.confere('sugestão fica aceita e com data de análise',
        (select status = 'aceita' and analisado_em is not null from sugestao_correcao where id = v_s1));
    select pontos into v_pontos from usuario where id = v_u;
    perform pg_temp.confere('o autor ganha 10 pontos', v_pontos = 10);

    call prc_analisar_sugestao(v_s2, true);
    perform pg_temp.confere('aceitar telefone atualiza o telefone', (select telefone = '(11) 5555-1234' from unidade where id = v_unidade));
    call prc_analisar_sugestao(v_s3, true);
    perform pg_temp.confere('aceitar endereço atualiza o endereço', (select endereco = 'Rua Nova, 100 - Centro' from unidade where id = v_unidade));
    call prc_analisar_sugestao(v_s4, false);
    perform pg_temp.confere('recusar não altera a unidade', (select ativo from unidade where id = v_unidade));
    perform pg_temp.confere('recusar não dá pontos', (select pontos from usuario where id = v_u) = 30);
    perform pg_temp.confere('sugestão recusada fica registrada', (select status from sugestao_correcao where id = v_s4) = 'recusada');

    begin
        call prc_analisar_sugestao(v_s1, true);
        v_erro := 'nenhum';
    exception when sqlstate 'PR011' then v_erro := 'PR011'; end;
    perform pg_temp.confere('analisar duas vezes a mesma sugestão é recusado', v_erro = 'PR011');

    begin
        call prc_analisar_sugestao(-1, true);
        v_erro := 'nenhum';
    exception when sqlstate 'PR011' then v_erro := 'PR011'; end;
    perform pg_temp.confere('sugestão inexistente é recusada', v_erro = 'PR011');

    -- Aceitar "fechada" desativa a unidade
    insert into sugestao_correcao (unidade_id, usuario_id, campo, descricao) values (v_unidade, v_u, 'fechada', 'Fechou em outubro') returning id into v_s4;
    call prc_analisar_sugestao(v_s4, true);
    perform pg_temp.confere('aceitar "fechada" desativa a unidade', not (select ativo from unidade where id = v_unidade));

    perform pg_temp.confere('o indicador conta sugestões por situação',
        (select sum(quantidade) from vw_sugestoes_resumo where status = 'aceita') = 4
        and (select sum(quantidade) from vw_sugestoes_resumo where status = 'recusada') = 1);
end;
$$;

rollback;
