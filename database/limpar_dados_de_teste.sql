-- Passa Rápido: remove os dados criados pelos testes automáticos do desenvolvimento.
-- Apaga APENAS contas com e-mail @example.com (e tudo ligado a elas, em cascata) e os avisos de teste de limite.
-- Contas reais (Gmail, FIAP etc.) não são tocadas. Rode no SQL Editor do Supabase quando quiser limpar.

do $$
declare
    v_contas integer;
begin
    if to_regclass('auth.users') is not null then
        select count(*) into v_contas from auth.users where email like '%@example.com';
        delete from usuario where id in (select id from auth.users where email like '%@example.com');
        delete from auth.users where email like '%@example.com';
        raise notice 'Contas de teste removidas: %', v_contas;
    end if;

    delete from relato where descricao in ('teste de limite', 'repetido') or descricao like 'teste de abuso%';
end;
$$;

-- Os registros de fila de teste viram parte do histórico por horário; recalcule a situação das unidades.
do $$
declare
    r record;
begin
    for r in select id from unidade where ativo loop
        call prc_recalcular_situacao(r.id);
    end loop;
end;
$$;
