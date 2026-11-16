-- Testes do script 14 (fonte oficial, acessibilidade, denúncias, moderação, consenso, impacto, gestão).
-- Exige um banco que imite o Supabase (schema auth, papéis anon/authenticated), como o preparado por tests/rodar_supabase_local.sh.
-- Uso: psql -v ON_ERROR_STOP=1 -d pr_supa14 -f tests/test_melhorias_14.sql
-- Roda dentro de uma transação e desfaz tudo ao final.
begin;

create or replace function pg_temp.confere(p_descricao text, p_condicao boolean) returns void
language plpgsql as $$
begin
    if p_condicao is not true then raise exception 'FALHOU: %', p_descricao; end if;
    raise notice 'ok: %', p_descricao;
end;
$$;
grant execute on function pg_temp.confere(text, boolean) to anon, authenticated;

do $$
declare
    v_un1   bigint;
    v_un2   bigint;
    v_un3   bigint;
    u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid();
    u4 uuid := gen_random_uuid(); u5 uuid := gen_random_uuid();
    v_erro  text;
    v_n     bigint;
    v_rel   bigint;
    v_ava   bigint;
    v_lat   double precision;
    v_lon   double precision;
    v_antes bigint;
    v_sug   bigint;
begin
    select id into v_un1 from unidade where ativo order by id offset 0 limit 1;
    select id into v_un2 from unidade where ativo order by id offset 1 limit 1;
    select id into v_un3 from unidade where ativo order by id offset 2 limit 1;
    insert into usuario (id, nome) values (u1, 'Ana Souza'), (u2, 'Bruno Lima'), (u3, 'Carla Dias'),
                                          (u4, 'Diego Melo'), (u5, 'Elisa Moderadora');

    ------------------------------------------------------------------------------------------
    -- 1. Fonte oficial
    ------------------------------------------------------------------------------------------
    select count(*) into v_antes from situacao_unidade where fonte in ('tempo_real', 'oficial');
    call prc_registrar_espera_oficial(v_un1, 12, 'Prefeitura de Teste', now() - interval '2 minutes');
    perform pg_temp.confere('leitura oficial vira a fonte da unidade',
        (select fonte from situacao_unidade where unidade_id = v_un1) = 'oficial'
        and (select espera_estimada_min from situacao_unidade where unidade_id = v_un1) = 12
        and (select confianca from situacao_unidade where unidade_id = v_un1) = 95);
    perform pg_temp.confere('a data da situação é a da leitura, não a do recálculo',
        (select atualizado_em from situacao_unidade where unidade_id = v_un1) <= now() - interval '110 seconds');
    perform pg_temp.confere('o painel conta a fonte oficial',
        (select count(*) from situacao_unidade where fonte in ('tempo_real', 'oficial')) >= v_antes);

    call prc_registrar_espera_oficial(v_un2, 40, 'Prefeitura de Teste', now() - interval '31 minutes');
    perform pg_temp.confere('leitura oficial velha (31 min) é ignorada', (select fonte from situacao_unidade where unidade_id = v_un2) <> 'oficial');

    begin call prc_registrar_espera_oficial(v_un1, 10, 'X', now() + interval '1 hour'); v_erro := 'nenhum';
    exception when sqlstate 'PR012' then v_erro := 'PR012'; end;
    perform pg_temp.confere('leitura no futuro é recusada', v_erro = 'PR012');
    begin call prc_registrar_espera_oficial(-1, 10, 'Origem'); v_erro := 'nenhum';
    exception when sqlstate 'PR012' then v_erro := 'PR012'; end;
    perform pg_temp.confere('unidade inexistente é recusada', v_erro = 'PR012');
    begin call prc_registrar_espera_oficial(v_un1, -5, 'Origem'); v_erro := 'nenhum';
    exception when check_violation then v_erro := 'check'; end;
    perform pg_temp.confere('espera negativa é recusada', v_erro = 'check');

    perform pg_temp.confere('o app (authenticated) não pode registrar leitura oficial',
        not has_function_privilege('authenticated', 'prc_registrar_espera_oficial(bigint,integer,text,timestamptz)', 'execute'));
    perform pg_temp.confere('visitante (anon) não pode registrar leitura oficial',
        not has_function_privilege('anon', 'prc_registrar_espera_oficial(bigint,integer,text,timestamptz)', 'execute'));

    -- alerta de fila baixa também dispara com leitura oficial
    insert into favorito (usuario_id, unidade_id, limite_espera_min, alerta_ativo) values (u1, v_un3, 20, true);
    call prc_registrar_espera_oficial(v_un3, 50, 'Prefeitura de Teste', now() - interval '2 minutes');
    call prc_registrar_espera_oficial(v_un3, 10, 'Prefeitura de Teste', now());
    perform pg_temp.confere('alerta de fila baixa dispara com dado oficial',
        (select count(*) from notificacao where usuario_id = u1 and unidade_id = v_un3) = 1);

    ------------------------------------------------------------------------------------------
    -- 2. Acessibilidade
    ------------------------------------------------------------------------------------------
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    insert into acessibilidade_voto (unidade_id, recurso, existe) values (v_un1, 'rampa', true);
    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into acessibilidade_voto (unidade_id, recurso, existe) values (v_un1, 'rampa', false);

    begin
        insert into acessibilidade_voto (unidade_id, usuario_id, recurso, existe) values (v_un1, u1, 'elevador', true);
        v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'rls'; end;
    perform pg_temp.confere('não dá para votar em nome de outra pessoa (RLS)', v_erro = 'rls');

    begin
        insert into acessibilidade_voto (unidade_id, recurso, existe) values (v_un1, 'cor_da_parede', true);
        v_erro := 'nenhum';
    exception when check_violation then v_erro := 'check'; end;
    perform pg_temp.confere('recurso desconhecido é recusado', v_erro = 'check');

    perform pg_temp.confere('cada pessoa enxerga só os próprios votos', (select count(*) from acessibilidade_voto) = 1);
    update acessibilidade_voto set existe = true where unidade_id = v_un1 and recurso = 'rampa';
    execute 'reset role';
    perform pg_temp.confere('mudar o próprio voto atualiza a contagem',
        (select sim from vw_acessibilidade_unidade where unidade_id = v_un1 and recurso = 'rampa') = 2);

    update configuracao set valor = '2' where chave = 'max_votos_acessibilidade_hora';
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into acessibilidade_voto (unidade_id, recurso, existe) values (v_un1, 'rampa', true), (v_un1, 'elevador', true);
    begin
        insert into acessibilidade_voto (unidade_id, recurso, existe) values (v_un1, 'libras', true);
        v_erro := 'nenhum';
    exception when sqlstate 'PR013' then v_erro := 'PR013'; end;
    perform pg_temp.confere('limite de votos por hora vale', v_erro = 'PR013');
    execute 'reset role';
    update configuracao set valor = '30' where chave = 'max_votos_acessibilidade_hora';

    execute 'set local role anon';
    begin
        insert into acessibilidade_voto (unidade_id, usuario_id, recurso, existe) values (v_un1, u1, 'vaga_pcd', true);
        v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não vota', v_erro = 'negado');
    perform pg_temp.confere('visitante lê a contagem pela view', (select count(*) from vw_acessibilidade_unidade) >= 1);
    execute 'reset role';

    ------------------------------------------------------------------------------------------
    -- 3. Denúncias
    ------------------------------------------------------------------------------------------
    insert into relato (unidade_id, usuario_id, tipo, descricao) values (v_un1, u1, 'outro', 'texto ofensivo') returning id into v_rel;
    insert into avaliacao (unidade_id, usuario_id, nota, comentario) values (v_un1, u1, 1, 'comentario ofensivo') returning id into v_ava;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    begin insert into denuncia (alvo, alvo_id, motivo) values ('relato', v_rel, 'ofensivo'); v_erro := 'nenhum';
    exception when sqlstate 'PR014' then v_erro := 'PR014'; end;
    perform pg_temp.confere('não dá para denunciar o próprio conteúdo', v_erro = 'PR014');

    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('relato', v_rel, 'ofensivo');
    begin insert into denuncia (alvo, alvo_id, motivo) values ('relato', v_rel, 'ofensivo'); v_erro := 'nenhum';
    exception when sqlstate 'PR014' then v_erro := 'PR014'; end;
    perform pg_temp.confere('denunciar duas vezes é recusado', v_erro = 'PR014');
    begin insert into denuncia (alvo, alvo_id, motivo) values ('relato', -7, 'falso'); v_erro := 'nenhum';
    exception when sqlstate 'PR014' then v_erro := 'PR014'; end;
    perform pg_temp.confere('conteúdo inexistente é recusado', v_erro = 'PR014');
    begin select count(*) into v_n from denuncia; v_erro := 'leu';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('o app não consegue ler denúncias', v_erro = 'negado');
    begin select count(*) into v_n from conteudo_oculto; v_erro := 'leu';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('o app não consegue ler texto ocultado', v_erro = 'negado');
    execute 'reset role';
    perform pg_temp.confere('uma denúncia não oculta', (select descricao from relato where id = v_rel) = 'texto ofensivo');

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('relato', v_rel, 'ofensivo');
    perform set_config('request.jwt.claim.sub', u4::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('relato', v_rel, 'spam');
    execute 'reset role';
    perform pg_temp.confere('três pessoas distintas ocultam o aviso',
        (select descricao from relato where id = v_rel) is null and (select expira_em from relato where id = v_rel) <= now());
    perform pg_temp.confere('o texto ocultado vai para a área restrita',
        (select texto from conteudo_oculto where alvo = 'relato' and alvo_id = v_rel) = 'texto ofensivo');

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('avaliacao', v_ava, 'ofensivo');
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('avaliacao', v_ava, 'ofensivo');
    perform set_config('request.jwt.claim.sub', u4::text, true);
    insert into denuncia (alvo, alvo_id, motivo) values ('avaliacao', v_ava, 'ofensivo');
    execute 'reset role';
    perform pg_temp.confere('avaliação denunciada perde o comentário e fica marcada, mas a nota continua',
        (select comentario from avaliacao where id = v_ava) is null
        and (select oculta from avaliacao where id = v_ava) and (select nota from avaliacao where id = v_ava) = 1);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    update avaliacao set comentario = 'volta a ofender', oculta = false where id = v_ava;
    execute 'reset role';
    perform pg_temp.confere('o autor não desfaz a ocultação editando',
        (select comentario from avaliacao where id = v_ava) is null and (select oculta from avaliacao where id = v_ava));

    execute 'set local role anon';
    begin insert into denuncia (alvo, alvo_id, usuario_id, motivo) values ('relato', v_rel, u2, 'falso'); v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não denuncia', v_erro = 'negado');
    execute 'reset role';

    ------------------------------------------------------------------------------------------
    -- 4. Moderação
    ------------------------------------------------------------------------------------------
    insert into moderador (usuario_id) values (u5);
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u2::text, true);
    begin perform * from fn_listar_denuncias_pendentes(); v_erro := 'nenhum';
    exception when sqlstate 'PR012' then v_erro := 'PR012'; end;
    perform pg_temp.confere('quem não é moderador não lista denúncias', v_erro = 'PR012');
    begin perform fn_resolver_denuncia('relato', v_rel, true); v_erro := 'nenhum';
    exception when sqlstate 'PR012' then v_erro := 'PR012'; end;
    perform pg_temp.confere('quem não é moderador não restaura conteúdo', v_erro = 'PR012');
    begin insert into moderador (usuario_id) values (u2); v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('ninguém se promove a moderador pelo app', v_erro = 'negado');
    perform pg_temp.confere('fn_sou_moderador é falso para usuário comum', not fn_sou_moderador());

    perform set_config('request.jwt.claim.sub', u5::text, true);
    perform pg_temp.confere('fn_sou_moderador é verdadeiro para moderador', fn_sou_moderador());
    perform pg_temp.confere('moderador vê as denúncias com o texto ocultado',
        exists (select 1 from fn_listar_denuncias_pendentes() where alvo = 'relato' and alvo_id = v_rel
                and texto = 'texto ofensivo' and denuncias = 3 and oculto));
    perform fn_resolver_denuncia('relato', v_rel, true);
    execute 'reset role';
    perform pg_temp.confere('moderador restaura o texto', (select descricao from relato where id = v_rel) = 'texto ofensivo');
    perform pg_temp.confere('a denúncia restaurada é encerrada', (select bool_and(resolvida) from denuncia where alvo = 'relato' and alvo_id = v_rel));

    execute 'set local role anon';
    begin perform fn_sou_moderador(); v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não chama rotinas de moderação', v_erro = 'negado');
    execute 'reset role';

    ------------------------------------------------------------------------------------------
    -- 5. Consenso de localização
    ------------------------------------------------------------------------------------------
    select latitude, longitude into v_lat, v_lon from unidade where id = v_un2;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude)
    values (v_un2, 'localizacao', 'O pino está errado', v_lat + 0.010, v_lon + 0.010);
    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude)
    values (v_un2, 'localizacao', 'O pino está errado', v_lat + 0.0100, v_lon + 0.0101);
    execute 'reset role';
    perform pg_temp.confere('duas pessoas ainda não bastam',
        (select count(*) from sugestao_correcao where unidade_id = v_un2 and status = 'pendente') = 2
        and (select latitude from unidade where id = v_un2) = v_lat);
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude)
    values (v_un2, 'localizacao', 'O pino está errado', v_lat + 0.0101, v_lon + 0.0100);
    execute 'reset role';
    perform pg_temp.confere('três pessoas distintas e confiáveis corrigem a localização',
        abs((select latitude from unidade where id = v_un2) - (v_lat + 0.0100)) < 0.0005
        and (select count(*) from sugestao_correcao where unidade_id = v_un2 and status = 'aceita') = 3);
    perform pg_temp.confere('cada autor ganha 10 pontos pelo consenso',
        (select count(*) from movimento_pontos where motivo = 'sugestao_aceita' and usuario_id in (u1, u2, u3)) = 3);

    -- pontos espalhados (cada um num lugar) não formam consenso
    select latitude, longitude into v_lat, v_lon from unidade where id = v_un3;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Aqui está certo', v_lat + 0.003, v_lon);
    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Aqui está certo', v_lat - 0.003, v_lon);
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Aqui está certo', v_lat, v_lon + 0.003);
    execute 'reset role';
    perform pg_temp.confere('pontos diferentes entre si não formam consenso',
        (select count(*) from sugestao_correcao where unidade_id = v_un3 and status = 'pendente') = 3);

    -- consenso com deslocamento enorme (acima de 5 km) espera um moderador
    select id into v_un3 from unidade where ativo and id not in (v_un1, v_un2, v_un3) order by id limit 1;
    select latitude, longitude into v_lat, v_lon from unidade where id = v_un3;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Fica longe daqui', v_lat + 0.5, v_lon);
    perform set_config('request.jwt.claim.sub', u2::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Fica longe daqui', v_lat + 0.5, v_lon);
    perform set_config('request.jwt.claim.sub', u3::text, true);
    insert into sugestao_correcao (unidade_id, campo, descricao, latitude, longitude) values (v_un3, 'localizacao', 'Fica longe daqui', v_lat + 0.5, v_lon) returning id into v_sug;
    execute 'reset role';
    perform pg_temp.confere('mudança acima de 5 km não é automática',
        (select count(*) from sugestao_correcao where unidade_id = v_un3 and status = 'pendente') = 3
        and (select latitude from unidade where id = v_un3) = v_lat);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u5::text, true);
    perform pg_temp.confere('moderador vê as pendentes com o número de apoios',
        exists (select 1 from fn_listar_sugestoes_pendentes() where id = v_sug and apoios = 2));
    perform fn_analisar_sugestao(v_sug, true);
    begin perform fn_analisar_sugestao(v_sug, true); v_erro := 'nenhum';
    exception when sqlstate 'PR011' then v_erro := 'PR011'; end;
    perform pg_temp.confere('moderador aceita uma vez; a segunda é recusada', v_erro = 'PR011');
    execute 'reset role';
    perform pg_temp.confere('a aceitação do moderador aplica a localização', (select latitude from unidade where id = v_un3) = v_lat + 0.5);

    ------------------------------------------------------------------------------------------
    -- 6. Impacto
    ------------------------------------------------------------------------------------------
    insert into registro_fila (unidade_id, usuario_id, tipo, tamanho_fila) values (v_un1, u4, 'observacao', 'curta');
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u4::text, true);
    perform pg_temp.confere('impacto conta só os registros da própria pessoa',
        (select registros_7d from fn_meu_impacto()) = 1 and (select unidades_7d from fn_meu_impacto()) = 1);
    execute 'reset role';
    execute 'set local role anon';
    begin perform * from fn_meu_impacto(); v_erro := 'nenhum';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não vê impacto', v_erro = 'negado');

    ------------------------------------------------------------------------------------------
    -- 7. Gestão por região (pública, agregada)
    ------------------------------------------------------------------------------------------
    perform pg_temp.confere('visitante lê a visão por região',
        (select count(*) from vw_gestao_regiao) > 0);
    execute 'reset role';
    perform pg_temp.confere('a visão cobre todas as unidades ativas',
        (select sum(unidades) from vw_gestao_regiao) = (select count(*) from unidade where ativo));
    perform pg_temp.confere('há hora de pico onde existe histórico', exists (select 1 from vw_gestao_regiao where hora_pico is not null));

    ------------------------------------------------------------------------------------------
    -- 8. Privacidade dos autores e endurecimento de permissões
    ------------------------------------------------------------------------------------------
    execute 'set local role anon';
    begin select count(*) into v_n from relato; v_erro := 'leu';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não lê a tabela de avisos (só a visão pública)', v_erro = 'negado');
    begin select count(*) into v_n from avaliacao; v_erro := 'leu';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('visitante não lê a tabela de avaliações', v_erro = 'negado');
    perform pg_temp.confere('visitante lê os avisos pela visão pública, sem identificar o autor',
        (select count(*) from vw_relato_publico where id = v_rel) = 1
        and (select proprio from vw_relato_publico where id = v_rel) = false);
    perform pg_temp.confere('a visão pública de avisos não tem a coluna usuario_id',
        not exists (select 1 from information_schema.columns where table_name = 'vw_relato_publico' and column_name = 'usuario_id'));
    perform pg_temp.confere('a visão pública de avaliações não tem a coluna usuario_id',
        not exists (select 1 from information_schema.columns where table_name = 'vw_avaliacao_publica' and column_name = 'usuario_id'));
    execute 'reset role';

    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u1::text, true);
    perform pg_temp.confere('a visão marca "proprio" só para o autor',
        (select proprio from vw_relato_publico where id = v_rel) = true
        and (select proprio from vw_avaliacao_publica where id = v_ava) = true);
    perform set_config('request.jwt.claim.sub', u2::text, true);
    perform pg_temp.confere('outra pessoa vê o aviso, mas não como dela',
        (select proprio from vw_relato_publico where id = v_rel) = false);
    perform pg_temp.confere('na tabela, cada pessoa só enxerga o que escreveu',
        (select count(*) from relato) = 0 and (select count(*) from avaliacao) = 0);
    begin insert into relato (unidade_id, tipo, descricao) values (v_un1, 'outro', 'novo aviso de teste'); v_erro := 'ok';
    exception when others then v_erro := sqlstate; end;
    perform pg_temp.confere('publicar aviso continua funcionando', v_erro = 'ok');
    begin update vw_relato_publico set descricao = 'x'; v_erro := 'alterou';
    exception when insufficient_privilege then v_erro := 'negado'; end;
    perform pg_temp.confere('a visão pública não aceita gravação', v_erro = 'negado');
    execute 'reset role';

    perform pg_temp.confere('app não executa funções de gatilho',
        not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
                       and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
    perform pg_temp.confere('app não executa rotinas internas',
        not has_function_privilege('authenticated', 'fn_ocultar_conteudo(text,bigint)', 'execute')
        and not has_function_privilege('authenticated', 'fn_resumo_dados_reais()', 'execute')
        and not has_function_privilege('anon', 'fn_meu_impacto()', 'execute')
        and not has_function_privilege('anon', 'confirmar_relato(bigint)', 'execute'));
    perform pg_temp.confere('ninguém no app tem TRUNCATE, REFERENCES ou TRIGGER nas tabelas',
        not exists (select 1 from information_schema.role_table_grants
                     where table_schema = 'public' and grantee in ('anon', 'authenticated')
                       and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')));
    perform pg_temp.confere('visitante não tem permissão de escrita em nenhuma tabela',
        not exists (select 1 from information_schema.role_table_grants
                     where table_schema = 'public' and grantee = 'anon' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')));
    perform pg_temp.confere('toda tabela do app tem segurança por linha',
        not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity));

    -- porta de entrada do órgão conveniado (chave de serviço): função e lote
    perform pg_temp.confere('o app não chama a porta de entrada do órgão',
        not has_function_privilege('authenticated', 'fn_registrar_espera_oficial(bigint,integer,text,timestamptz)', 'execute')
        and not has_function_privilege('anon', 'fn_registrar_esperas_oficiais(jsonb)', 'execute')
        and has_function_privilege('service_role', 'fn_registrar_esperas_oficiais(jsonb)', 'execute'));
    v_n := fn_registrar_esperas_oficiais(jsonb_build_array(
            jsonb_build_object('unidade_id', v_un1, 'espera_min', 22, 'origem', 'Prefeitura de Teste'),
            jsonb_build_object('unidade_id', v_un2, 'espera_min', 33, 'origem', 'Prefeitura de Teste')));
    perform pg_temp.confere('lote oficial grava todas as leituras',
        v_n = 2 and (select espera_estimada_min from situacao_unidade where unidade_id = v_un2) = 33);
    begin perform fn_registrar_esperas_oficiais(jsonb_build_array(
            jsonb_build_object('unidade_id', v_un1, 'espera_min', 10, 'origem', 'Origem boa'),
            jsonb_build_object('unidade_id', v_un1, 'espera_min', -3, 'origem', 'Origem ruim'))); v_erro := 'nenhum';
    exception when check_violation then v_erro := 'check'; end;
    perform pg_temp.confere('lote com leitura inválida é recusado', v_erro = 'check');
    begin perform fn_registrar_esperas_oficiais('{"a":1}'::jsonb); v_erro := 'nenhum';
    exception when sqlstate 'PR012' then v_erro := 'PR012'; end;
    perform pg_temp.confere('lote que não é lista é recusado', v_erro = 'PR012');
end;
$$;

rollback;
