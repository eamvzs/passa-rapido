-- Testes das rotinas do banco. Executa dentro de uma transação e desfaz tudo ao final.
-- Uso: psql -v ON_ERROR_STOP=1 -d passa_rapido -f tests/test_rotinas.sql
begin;

create or replace function pg_temp.confere(p_descricao text, p_condicao boolean) returns void
language plpgsql as $$
begin
    if p_condicao is not true then
        raise exception 'FALHOU: %', p_descricao;
    end if;
    raise notice 'ok: %', p_descricao;
end;
$$;

do $$
declare
    v_tipo     smallint;
    v_unidade  bigint;
    v_outra    bigint;
    v_ana      uuid := gen_random_uuid();
    v_beto     uuid := gen_random_uuid();
    v_caio     uuid := gen_random_uuid();
    v_registro bigint;
    v_sit      situacao_unidade;
    v_pontos   integer;
    v_total    integer;
    v_relato   bigint;
    v_erro     text;
begin
    select id into v_tipo from tipo_unidade where nome = 'UPA';
    insert into unidade (tipo_unidade_id, nome, endereco, cidade, uf, latitude, longitude)
    values (v_tipo, 'UPA Teste', 'Rua A', 'São Paulo', 'SP', -23.55, -46.63) returning id into v_unidade;
    insert into unidade (tipo_unidade_id, nome, endereco, cidade, uf, latitude, longitude)
    values (v_tipo, 'UPA Teste 2', 'Rua B', 'São Paulo', 'SP', -23.56, -46.64) returning id into v_outra;
    insert into usuario (id, nome) values (v_ana, 'Ana Teste'), (v_beto, 'Beto Teste'), (v_caio, 'Caio Teste');

    select * into v_sit from situacao_unidade where unidade_id = v_unidade;
    perform pg_temp.confere('unidade nova nasce com situação sem dados', v_sit.nivel = 'sem_dados');

    -- Check-in: situação passa a tempo real e o usuário pontua.
    insert into registro_fila (unidade_id, usuario_id, tamanho_fila, chegada_em)
    values (v_unidade, v_ana, 'media', now() - interval '30 minutes') returning id into v_registro;
    select * into v_sit from situacao_unidade where unidade_id = v_unidade;
    perform pg_temp.confere('check-in gera estimativa em tempo real',
        v_sit.fonte = 'tempo_real' and v_sit.espera_estimada_min = 40 and v_sit.pessoas_aguardando = 1);
    select pontos into v_pontos from usuario where id = v_ana;
    perform pg_temp.confere('check-in credita 5 pontos', v_pontos = 5);

    -- Registro repetido em menos de 10 minutos é bloqueado.
    begin
        insert into registro_fila (unidade_id, usuario_id, tamanho_fila, chegada_em)
        values (v_unidade, v_ana, 'longa', now() - interval '25 minutes');
        v_erro := 'nenhum';
    exception when sqlstate 'PR001' then
        v_erro := 'PR001';
    end;
    perform pg_temp.confere('registro repetido é bloqueado', v_erro = 'PR001');

    -- Atendimento: calcula a espera real, muda o status e credita 10 pontos.
    update registro_fila set atendido_em = now() - interval '5 minutes' where id = v_registro;
    perform pg_temp.confere('atendimento calcula a espera real de 25 minutos',
        (select espera_real_min = 25 and status = 'atendido' from registro_fila where id = v_registro));
    select pontos into v_pontos from usuario where id = v_ana;
    perform pg_temp.confere('atendimento confirmado credita 10 pontos', v_pontos = 15);
    select * into v_sit from situacao_unidade where unidade_id = v_unidade;
    perform pg_temp.confere('estimativa usa a espera medida',
        v_sit.espera_estimada_min = 25 and v_sit.pessoas_aguardando = 0);

    -- Novo check-in em outra unidade encerra o anterior do mesmo usuário.
    insert into registro_fila (unidade_id, usuario_id, tamanho_fila) values (v_unidade, v_beto, 'curta');
    insert into registro_fila (unidade_id, usuario_id, tamanho_fila) values (v_outra, v_beto, 'curta');
    perform pg_temp.confere('usuário só fica em uma fila por vez',
        (select count(*) = 1 from registro_fila where usuario_id = v_beto and status = 'aguardando'));

    -- Reputação: 50 pontos elevam o nível e o peso dos próximos registros.
    insert into movimento_pontos (usuario_id, pontos, motivo) values (v_ana, 40, 'relato');
    perform pg_temp.confere('nível sobe para colaborador com 50 pontos ou mais',
        (select nivel = 'colaborador' from usuario where id = v_ana));
    perform pg_temp.confere('peso do colaborador é 1.5', fn_peso_usuario(v_ana) = 1.5);

    -- Alerta de fila baixa para quem favoritou.
    insert into favorito (usuario_id, unidade_id, limite_espera_min) values (v_ana, v_outra, 10);
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila, chegada_em)
    values (v_outra, v_ana, 'observacao', 'lotada', now() - interval '1 minute');
    perform pg_temp.confere('sem alerta enquanto a espera está acima do limite',
        (select count(*) = 0 from notificacao where usuario_id = v_ana));
    update registro_fila set status = 'expirado' where unidade_id = v_outra;
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila)
    values (v_outra, v_caio, 'observacao', 'sem_fila');
    perform pg_temp.confere('alerta criado quando a espera cai abaixo do limite',
        (select count(*) = 1 from notificacao where usuario_id = v_ana and unidade_id = v_outra));

    -- Relatos e confirmações.
    insert into relato (unidade_id, usuario_id, tipo) values (v_unidade, v_ana, 'sem_medico')
    returning id into v_relato;
    v_total := fn_confirmar_relato(v_relato, v_beto);
    perform pg_temp.confere('confirmação soma no contador do relato', v_total = 1);
    begin
        perform fn_confirmar_relato(v_relato, v_ana);
        v_erro := 'nenhum';
    exception when sqlstate 'PR003' then
        v_erro := 'PR003';
    end;
    perform pg_temp.confere('autor não confirma o próprio relato', v_erro = 'PR003');
    begin
        perform fn_confirmar_relato(v_relato, v_beto);
        v_erro := 'nenhum';
    exception when sqlstate 'PR004' then
        v_erro := 'PR004';
    end;
    perform pg_temp.confere('confirmação duplicada é recusada', v_erro = 'PR004');

    -- Expiração de check-ins esquecidos.
    alter table registro_fila disable trigger trg_registro_antes_inserir;
    insert into registro_fila (unidade_id, usuario_id, tamanho_fila, chegada_em)
    values (v_unidade, v_beto, 'longa', now() - interval '8 hours') returning id into v_registro;
    alter table registro_fila enable trigger trg_registro_antes_inserir;
    call prc_expirar_registros();
    perform pg_temp.confere('check-in com mais de 6 horas expira',
        (select status = 'expirado' from registro_fila where id = v_registro));

    -- Funções de apoio.
    perform pg_temp.confere('distância Sé até Paulista fica entre 2 e 4 km',
        fn_distancia_km(-23.5505, -46.6333, -23.5614, -46.6559) between 2 and 4);
    perform pg_temp.confere('recomendação ordena pelo menor tempo total',
        (select tempo_total_min from fn_recomendar_unidades(-23.55, -46.63) limit 1)
        = (select min(tempo_total_min) from fn_recomendar_unidades(-23.55, -46.63)));
    perform pg_temp.confere('melhor horário marca exatamente a menor média',
        (select bool_and(melhor = (media_espera_min = (select min(media_espera_min)
                                                         from fn_melhor_horario(13, 1::smallint))))
           from fn_melhor_horario(13, 1::smallint)));
end;
$$;

rollback;
