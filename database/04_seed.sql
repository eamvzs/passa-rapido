-- Passa Rápido: dados de demonstração (cidade de São Paulo)
-- ATENÇÃO: as unidades abaixo têm localização APROXIMADA por bairro e as filas são simuladas.
-- Servem para demonstrar o app; para uso real, carregar as unidades de fontes oficiais.

select setseed(0.42);

insert into tipo_unidade (nome, icone, cor_hex) values
    ('UPA',            'emergency',        '#C62828'),
    ('Pronto-socorro', 'local_hospital',   '#AD1457'),
    ('UBS',            'medical_services', '#2E7D32'),
    ('Poupatempo',     'badge',            '#1565C0'),
    ('INSS',           'account_balance',  '#EF6C00'),
    ('CRAS',           'diversity_3',      '#6A1B9A');

insert into servico (nome, descricao, documentos_necessarios) values
    ('Clínico geral',            'Atendimento médico de urgência para adultos',  'Documento com foto e cartão do SUS'),
    ('Pediatria',                'Atendimento médico de urgência para crianças', 'Documento do responsável, certidão ou RG da criança e cartão do SUS'),
    ('Ortopedia',                'Fraturas, torções e dores musculares',         'Documento com foto e cartão do SUS'),
    ('Vacinação',                'Vacinas do calendário nacional',               'Documento com foto e caderneta de vacinação'),
    ('Medicação e curativos',    'Aplicação de medicamentos e troca de curativos', 'Documento com foto e receita médica'),
    ('Carteira de identidade',   'Primeira via e segunda via do RG',             'Certidão de nascimento ou casamento e CPF'),
    ('CNH',                      'Renovação e segunda via da habilitação',       'CNH atual, CPF e comprovante de endereço'),
    ('Seguro-desemprego',        'Solicitação do benefício',                     'Requerimento do empregador, carteira de trabalho e documento com foto'),
    ('Perícia médica',           'Perícia para benefícios por incapacidade',     'Documento com foto, laudos e exames'),
    ('Aposentadoria e benefícios', 'Orientação e requerimento de benefícios',    'Documento com foto, CPF e carteira de trabalho'),
    ('Cadastro Único',           'Inscrição e atualização do CadÚnico',          'CPF ou título de eleitor de todos os moradores e comprovante de endereço'),
    ('Bolsa Família',            'Orientação e acompanhamento do benefício',     'Documento com foto e número do NIS');

insert into unidade (tipo_unidade_id, nome, endereco, bairro, cidade, uf, latitude, longitude)
select t.id, v.nome, 'Localização aproximada (dado de demonstração)', v.bairro, 'São Paulo', 'SP', v.lat, v.lng
  from (values
    ('UPA',            'UPA Vila Mariana',                'Vila Mariana',  -23.5893, -46.6350),
    ('UPA',            'UPA Santo Amaro',                 'Santo Amaro',   -23.6536, -46.7106),
    ('UPA',            'UPA Tatuapé',                     'Tatuapé',       -23.5403, -46.5766),
    ('UPA',            'UPA Campo Limpo',                 'Campo Limpo',   -23.6490, -46.7590),
    ('UPA',            'UPA Pirituba',                    'Pirituba',      -23.4870, -46.7260),
    ('Pronto-socorro', 'Pronto-Socorro Lapa',             'Lapa',          -23.5270, -46.7030),
    ('Pronto-socorro', 'Pronto-Socorro Santana',          'Santana',       -23.5020, -46.6250),
    ('UBS',            'UBS Sé',                          'Sé',            -23.5480, -46.6340),
    ('UBS',            'UBS Pinheiros',                   'Pinheiros',     -23.5630, -46.6900),
    ('UBS',            'UBS Itaquera',                    'Itaquera',      -23.5360, -46.4560),
    ('UBS',            'UBS Butantã',                     'Butantã',       -23.5710, -46.7080),
    ('UBS',            'UBS Mooca',                       'Mooca',         -23.5600, -46.5990),
    ('Poupatempo',     'Poupatempo Sé',                   'Sé',            -23.5499, -46.6310),
    ('Poupatempo',     'Poupatempo Santo Amaro',          'Santo Amaro',   -23.6510, -46.7080),
    ('Poupatempo',     'Poupatempo Itaquera',             'Itaquera',      -23.5420, -46.4710),
    ('Poupatempo',     'Poupatempo Lapa',                 'Lapa',          -23.5200, -46.7010),
    ('INSS',           'Agência INSS Centro',             'República',     -23.5440, -46.6390),
    ('INSS',           'Agência INSS Santana',            'Santana',       -23.5010, -46.6280),
    ('INSS',           'Agência INSS Santo Amaro',        'Santo Amaro',   -23.6480, -46.7040),
    ('INSS',           'Agência INSS Tatuapé',            'Tatuapé',       -23.5380, -46.5650),
    ('CRAS',           'CRAS Sé',                         'Sé',            -23.5465, -46.6365),
    ('CRAS',           'CRAS Capão Redondo',              'Capão Redondo', -23.6690, -46.7790),
    ('CRAS',           'CRAS Brasilândia',                'Brasilândia',   -23.4690, -46.6900)
  ) as v (tipo, nome, bairro, lat, lng)
  join tipo_unidade t on t.nome = v.tipo;

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
            and s.nome in ('Cadastro Único', 'Bolsa Família'));

-- UPA e pronto-socorro: 24 horas. Demais: dias úteis das 8h às 17h. Poupatempo abre aos sábados.
insert into horario_funcionamento (unidade_id, dia_semana, abre, fecha)
select u.id, d, time '00:00', time '23:59:59'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id, generate_series(0, 6) d
 where t.nome in ('UPA', 'Pronto-socorro')
union all
select u.id, d, time '08:00', time '17:00'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id, generate_series(1, 5) d
 where t.nome not in ('UPA', 'Pronto-socorro')
union all
select u.id, 6, time '09:00', time '13:00'
  from unidade u join tipo_unidade t on t.id = u.tipo_unidade_id
 where t.nome = 'Poupatempo';

insert into usuario (id, nome, pontos, nivel) values
    ('00000000-0000-4000-8000-000000000001', 'Ana Souza',        320, 'confiavel'),
    ('00000000-0000-4000-8000-000000000002', 'Bruno Lima',       245, 'confiavel'),
    ('00000000-0000-4000-8000-000000000003', 'Carla Mendes',     180, 'colaborador'),
    ('00000000-0000-4000-8000-000000000004', 'Diego Rocha',      130, 'colaborador'),
    ('00000000-0000-4000-8000-000000000005', 'Elaine Costa',      95, 'colaborador'),
    ('00000000-0000-4000-8000-000000000006', 'Fábio Santos',      60, 'colaborador'),
    ('00000000-0000-4000-8000-000000000007', 'Gabriela Alves',    40, 'iniciante'),
    ('00000000-0000-4000-8000-000000000008', 'Henrique Dias',     25, 'iniciante'),
    ('00000000-0000-4000-8000-000000000009', 'Isabela Ferreira',  15, 'iniciante'),
    ('00000000-0000-4000-8000-000000000010', 'João Pereira',      10, 'iniciante'),
    ('00000000-0000-4000-8000-000000000011', 'Karina Oliveira',    5, 'iniciante'),
    ('00000000-0000-4000-8000-000000000012', 'Lucas Martins',      0, 'iniciante');

-- Carga em massa sem disparar os triggers linha a linha; a consolidação é feita ao final.
alter table registro_fila disable trigger user;

-- Histórico dos últimos 21 dias: dois registros por hora de funcionamento em cada unidade.
-- A espera segue uma curva com picos às 10h e às 15h, maior às segundas e menor no fim de semana.
-- O CRAS Brasilândia fica sem histórico para demonstrar o estado "sem dados".
insert into registro_fila
    (unidade_id, usuario_id, tipo, tamanho_fila, status, chegada_em, atendido_em, saida_em, espera_real_min, peso)
select g.unidade_id, g.usuario_id, 'checkin',
       case when g.espera <= 5 then 'sem_fila' when g.espera <= 25 then 'curta'
            when g.espera <= 60 then 'media' when g.espera <= 110 then 'longa' else 'lotada' end,
       'concluido',
       g.chegada, g.chegada + make_interval(mins => g.espera),
       g.chegada + make_interval(mins => g.espera + 20),
       g.espera, 1.0
  from (
    select u.id as unidade_id,
           ('00000000-0000-4000-8000-0000000000' || lpad((1 + floor(random() * 12))::int::text, 2, '0'))::uuid as usuario_id,
           ((date_trunc('day', now() at time zone 'America/Sao_Paulo')
                - make_interval(days => d) + make_interval(hours => h, mins => (floor(random() * 50))::int))
                at time zone 'America/Sao_Paulo') as chegada,
           greatest(0, round(
               case t.nome when 'UPA' then 55 when 'Pronto-socorro' then 80 when 'UBS' then 30
                           when 'Poupatempo' then 28 when 'INSS' then 42 else 18 end
               * (0.45 + 0.9 * exp(-((h - 10) ^ 2) / 8.0) + 0.7 * exp(-((h - 15) ^ 2) / 8.0)
                       + case when t.nome in ('UPA', 'Pronto-socorro') then 0.5 * exp(-((h - 20) ^ 2) / 6.0) else 0 end)
               * case extract(dow from (now() at time zone 'America/Sao_Paulo')::date - d)
                      when 1 then 1.3 when 5 then 1.1 when 0 then 0.75 when 6 then 0.8 else 1.0 end
               * (0.7 + random() * 0.6)
           ))::int as espera
      from unidade u
      join tipo_unidade t on t.id = u.tipo_unidade_id
      cross join generate_series(1, 21) d
      cross join generate_series(0, 23) h
      cross join generate_series(1, 2) amostra
      join horario_funcionamento f
        on f.unidade_id = u.id
       and f.dia_semana = extract(dow from (now() at time zone 'America/Sao_Paulo')::date - d)
       and make_time(h, 0, 0) >= f.abre and make_time(h, 0, 0) < f.fecha
     where u.nome <> 'CRAS Brasilândia'
  ) g;

-- Movimento da última hora, para o mapa abrir com dados em tempo real.
insert into registro_fila
    (unidade_id, usuario_id, tipo, tamanho_fila, status, chegada_em, atendido_em, espera_real_min, peso)
select u.id,
       ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid,
       v.tipo, v.tamanho, v.status,
       now() - make_interval(mins => v.min_atras),
       case when v.espera is not null then now() - make_interval(mins => v.min_atras - v.espera) end,
       v.espera,
       v.peso
  from (values
    ('UPA Vila Mariana',         1, 'checkin',    'lotada',   'aguardando', 95,  null, 2.0),
    ('UPA Vila Mariana',         4, 'checkin',    'longa',    'atendido',   110, 100,  1.5),
    ('UPA Vila Mariana',         7, 'observacao', 'lotada',   'concluido',  12,  null, 1.0),
    ('UPA Santo Amaro',          2, 'checkin',    'media',    'atendido',   50,  38,   2.0),
    ('UPA Santo Amaro',          8, 'observacao', 'media',    'concluido',  9,   null, 1.0),
    ('UPA Tatuapé',              3, 'checkin',    'curta',    'atendido',   30,  12,   1.5),
    ('UPA Tatuapé',              9, 'observacao', 'curta',    'concluido',  6,   null, 1.0),
    ('UPA Campo Limpo',          5, 'checkin',    'longa',    'aguardando', 62,  null, 1.5),
    ('UPA Pirituba',             6, 'observacao', 'sem_fila', 'concluido',  14,  null, 1.5),
    ('Pronto-Socorro Lapa',      10, 'checkin',   'lotada',   'aguardando', 130, null, 1.0),
    ('Pronto-Socorro Lapa',      2, 'observacao', 'lotada',   'concluido',  20,  null, 2.0),
    ('Pronto-Socorro Santana',   11, 'checkin',   'media',    'atendido',   70,  45,   1.0),
    ('UBS Sé',                   1, 'observacao', 'curta',    'concluido',  18,  null, 2.0),
    ('UBS Pinheiros',            3, 'checkin',    'sem_fila', 'atendido',   25,  4,    1.5),
    ('UBS Itaquera',             4, 'checkin',    'media',    'aguardando', 33,  null, 1.5),
    ('Poupatempo Sé',            5, 'checkin',    'longa',    'atendido',   90,  72,   1.5),
    ('Poupatempo Sé',            12, 'observacao','longa',    'concluido',  8,   null, 1.0),
    ('Poupatempo Santo Amaro',   6, 'checkin',    'curta',    'atendido',   40,  18,   1.5),
    ('Poupatempo Itaquera',      7, 'observacao', 'media',    'concluido',  22,  null, 1.0),
    ('Agência INSS Centro',      8, 'checkin',    'longa',    'aguardando', 75,  null, 1.0),
    ('Agência INSS Santana',     9, 'checkin',    'curta',    'atendido',   35,  14,   1.0),
    ('CRAS Sé',                  10, 'observacao','sem_fila', 'concluido',  16,  null, 1.0)
  ) as v (unidade, usuario, tipo, tamanho, status, min_atras, espera, peso)
  join unidade u on u.nome = v.unidade;

alter table registro_fila enable trigger user;

call prc_consolidar_historico(60);
call prc_expirar_registros();

insert into relato (unidade_id, usuario_id, tipo, descricao)
select u.id, ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid, v.tipo, v.descricao
  from (values
    ('UPA Vila Mariana',    1, 'sem_medico',         'Sem pediatra no plantão desta tarde'),
    ('Poupatempo Sé',       5, 'sistema_fora',       'Sistema do RG fora do ar, sem previsão'),
    ('UBS Pinheiros',       3, 'atendimento_normal', 'Atendimento rápido e vacinas disponíveis'),
    ('UBS Itaquera',        4, 'sem_vacina',         'Vacina da gripe em falta'),
    ('Agência INSS Centro', 8, 'sem_senha',          'Senhas do dia esgotadas às 10h')
  ) as v (unidade, usuario, tipo, descricao)
  join unidade u on u.nome = v.unidade;

insert into avaliacao (unidade_id, usuario_id, nota, comentario)
select u.id, ('00000000-0000-4000-8000-0000000000' || lpad(v.usuario::text, 2, '0'))::uuid, v.nota, v.comentario
  from (values
    ('UPA Vila Mariana',  1, 3, 'Atendimento bom, mas a espera é longa'),
    ('UPA Vila Mariana',  4, 2, 'Fiquei quase duas horas esperando'),
    ('UPA Tatuapé',       3, 5, 'Fui atendido rápido'),
    ('UBS Pinheiros',     3, 5, 'Equipe atenciosa'),
    ('Poupatempo Sé',     5, 4, 'Organizado, mas cheio no horário de almoço'),
    ('Poupatempo Lapa',   2, 5, 'Resolvi tudo em meia hora')
  ) as v (unidade, usuario, nota, comentario)
  join unidade u on u.nome = v.unidade;

insert into favorito (usuario_id, unidade_id, limite_espera_min)
select '00000000-0000-4000-8000-000000000012', u.id, 30
  from unidade u where u.nome in ('UPA Vila Mariana', 'Poupatempo Sé');
