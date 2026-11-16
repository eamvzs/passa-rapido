-- Passa Rápido: remove tudo o que é simulado ou de teste, para o app mostrar apenas dado real.
-- Rode no SQL Editor do Supabase. É seguro repetir.
--
-- O que faz:
--   1. desliga o simulador de movimento do pg_cron;
--   2. apaga os 12 usuários fictícios do cadastro de demonstração (e, em cascata, tudo que eles
--      registraram: filas, relatos, avaliações, favoritos, alertas, pontos);
--   3. apaga as contas de teste (@example.com) e os relatos de teste de limite;
--   4. apaga o histórico que foi calculado a partir desses registros e o recalcula só com o que restou
--      (registros de cidadãos reais), mantendo a estimativa do modelo (qtd_amostras = 0) onde não há dado;
--   5. recalcula a situação de todas as unidades ativas.
--
-- Não apaga: unidades (reais ou de demonstração inativas), serviços, horários, contas reais.

do $$
declare
    v_demo     integer;
    v_contas   integer := 0;
begin
    -- 1. Simulador.
    if to_regclass('cron.job') is not null then
        perform cron.unschedule(jobid) from cron.job where jobname = 'passa-rapido-simulador';
    end if;

    -- 2. Usuários fictícios do seed (UUID 00000000-0000-4000-8000-...).
    select count(*) into v_demo from usuario where id::text like '00000000-0000-4000-8000-%';
    delete from usuario where id::text like '00000000-0000-4000-8000-%';

    -- 3. Contas e relatos de teste.
    if to_regclass('auth.users') is not null then
        select count(*) into v_contas from auth.users where email like '%@example.com';
        delete from usuario where id in (select id from auth.users where email like '%@example.com');
        delete from auth.users where email like '%@example.com';
    end if;
    delete from relato where descricao in ('teste de limite', 'repetido') or descricao like 'teste de abuso%';

    raise notice 'Usuários fictícios removidos: %; contas de teste removidas: %', v_demo, v_contas;
end;
$$;

-- 4. Histórico: sai o que veio de dados simulados; entra o que existe de registro real; o resto volta ao modelo.
delete from historico_espera where qtd_amostras > 0;
call prc_consolidar_historico(60);
call prc_completar_unidades_reais();

-- 5. Situação de todas as unidades ativas.
do $$
declare
    r record;
begin
    for r in select id from unidade where ativo order by id loop
        begin
            call prc_recalcular_situacao(r.id);
        exception when others then
            raise warning 'Falha ao recalcular a unidade %: %', r.id, sqlerrm;
        end;
    end loop;
end;
$$;

-- Conferência: deve mostrar 0 usuários fictícios, 0 registros fictícios e o simulador ausente.
select (select count(*) from usuario where id::text like '00000000-0000-4000-8000-%')   as usuarios_ficticios,
       (select count(*) from registro_fila)                                              as registros_de_fila,
       (select count(*) from relato)                                                     as relatos,
       (select count(*) from historico_espera where qtd_amostras > 0)                    as horas_com_dado_real,
       (select count(*) from historico_espera where qtd_amostras = 0)                    as horas_estimadas_pelo_modelo,
       case when to_regclass('cron.job') is null then null
            else (xpath('/row/c/text()', query_to_xml(
                    'select count(*) as c from cron.job where jobname = ''passa-rapido-simulador''',
                    false, true, '')))[1]::text::integer end                             as simulador_agendado;
