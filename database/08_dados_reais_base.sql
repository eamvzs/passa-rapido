-- Passa Rápido: parte estática da importação de unidades reais (sem dados; idempotente).
-- Aplique depois de 07_estrutura_dados_reais.sql e 10_cnes.sql e ANTES de 08_unidades_reais.sql / 10_unidades_cnes.sql.
--
-- prc_completar_unidades_reais() prepara as unidades com origem 'openstreetmap' ou 'cnes':
--   (a) vincula os serviços de cada tipo;
--   (b) cria o horário de funcionamento PADRÃO por tipo, quando a unidade não tem horário;
--   (c) gera um histórico de espera ESTIMADO (modelo, não dado de cidadãos): qtd_amostras = 0.
--       Quando houver registros reais, prc_consolidar_historico sobrescreve essas linhas
--       (on conflict ... do update) e passa a gravar a quantidade real de amostras;
--   (d) garante a linha de situação de cada unidade;
--   (e) desativa as unidades de demonstração, somente se existir ao menos uma unidade real ativa;
--   (f) recalcula a situação de cada unidade importada.

create or replace procedure prc_completar_unidades_reais()
language plpgsql security definer set search_path = public as $$
declare
    c_unidades cursor for
        select id from unidade where origem in ('openstreetmap', 'cnes') and ativo order by id;
    v_item record;
begin
    -- (a) Serviços por tipo (mesmo mapeamento dos dados de demonstração).
    insert into unidade_servico (unidade_id, servico_id)
    select u.id, s.id
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      join servico s on
           (t.nome in ('UPA', 'Pronto-socorro')
                and s.nome in ('Clínico geral', 'Pediatria', 'Ortopedia', 'Medicação e curativos'))
        or (t.nome = 'UBS'
                and s.nome in ('Clínico geral', 'Pediatria', 'Vacinação', 'Medicação e curativos'))
        or (t.nome = 'Poupatempo'
                and s.nome in ('Carteira de identidade', 'CNH', 'Seguro-desemprego'))
        or (t.nome = 'INSS'
                and s.nome in ('Perícia médica', 'Aposentadoria e benefícios'))
        or (t.nome = 'CRAS'
                and s.nome in ('Cadastro Único', 'Bolsa Família'))
     where u.origem in ('openstreetmap', 'cnes')
    on conflict do nothing;

    -- (b) Horário padrão, só para unidades que ainda não têm nenhum horário.
    --     UPA e pronto-socorro: 24 horas. Demais: segunda a sexta, 8h às 17h. Poupatempo também abre sábado, 9h às 13h.
    insert into horario_funcionamento (unidade_id, dia_semana, abre, fecha)
    select u.id, d.dia, time '00:00', time '23:59:59'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(0, 6) as d (dia)
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome in ('UPA', 'Pronto-socorro')
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    union all
    select u.id, d.dia, time '08:00', time '17:00'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(1, 5) as d (dia)
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome not in ('UPA', 'Pronto-socorro')
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    union all
    select u.id, 6, time '09:00', time '13:00'
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
     where u.origem in ('openstreetmap', 'cnes')
       and t.nome = 'Poupatempo'
       and not exists (select 1 from horario_funcionamento h where h.unidade_id = u.id)
    on conflict do nothing;

    -- (c) Histórico estimado: mesma curva dos dados de demonstração (picos às 10h e 15h,
    --     pico noturno em UPA e pronto-socorro, segunda mais cheia, fim de semana mais vazio),
    --     com ruído determinístico por hash para o resultado ser reprodutível.
    --     Só entra onde ainda não existe linha: dados de cidadãos nunca são sobrescritos aqui.
    insert into historico_espera (unidade_id, dia_semana, hora, media_espera_min, qtd_amostras, atualizado_em)
    select u.id, f.dia_semana, g.hora::smallint,
           greatest(0, round(
               case t.nome when 'UPA' then 55 when 'Pronto-socorro' then 80 when 'UBS' then 30
                           when 'Poupatempo' then 28 when 'INSS' then 42 else 18 end
               * (0.45 + 0.9 * exp(-((g.hora - 10) ^ 2) / 8.0) + 0.7 * exp(-((g.hora - 15) ^ 2) / 8.0)
                       + case when t.nome in ('UPA', 'Pronto-socorro')
                              then 0.5 * exp(-((g.hora - 20) ^ 2) / 6.0) else 0 end)
               * case f.dia_semana when 1 then 1.3 when 5 then 1.1 when 0 then 0.75 when 6 then 0.8 else 1.0 end
               * (0.7 + 0.6 * ((abs(hashtext(u.id::text || '-' || f.dia_semana::text || '-' || g.hora::text)::bigint) % 1000) / 1000.0))
           ))::integer,
           0,
           now()
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      join horario_funcionamento f on f.unidade_id = u.id
      cross join generate_series(0, 23) as g (hora)
     where u.origem in ('openstreetmap', 'cnes')
       and make_time(g.hora, 0, 0) >= f.abre
       and make_time(g.hora, 0, 0) < f.fecha
    on conflict (unidade_id, dia_semana, hora) do nothing;

    -- (d) Linha de situação de cada unidade (o trigger de inserção já cria; aqui só garante).
    insert into situacao_unidade (unidade_id)
    select u.id from unidade u where u.origem in ('openstreetmap', 'cnes')
    on conflict (unidade_id) do nothing;

    -- (e) Troca os dados de demonstração pelos reais, mas nunca deixa o app sem unidades.
    if exists (select 1 from unidade where origem in ('openstreetmap', 'cnes') and ativo) then
        update unidade set ativo = false where origem = 'demonstracao' and ativo;
    end if;

    -- (f) Recalcula a situação de cada unidade importada; uma falha não interrompe as demais.
    for v_item in c_unidades loop
        begin
            call prc_recalcular_situacao(v_item.id);
        exception when others then
            raise warning 'Falha ao recalcular a unidade %: %', v_item.id, sqlerrm;
        end;
    end loop;
end;
$$;

-- Contagem de unidades por tipo e origem, para conferir a importação.
create or replace function fn_resumo_dados_reais()
returns table (tipo text, origem text, ativas bigint, total bigint)
language sql stable security definer set search_path = public as $$
    select t.nome, u.origem,
           count(*) filter (where u.ativo),
           count(*)
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
     group by t.nome, u.origem
     order by u.origem, t.nome;
$$;

-- O procedimento é de manutenção: no Supabase só o administrador deve executá-lo.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on procedure prc_completar_unidades_reais() from public, anon, authenticated;
    end if;
end;
$$;
