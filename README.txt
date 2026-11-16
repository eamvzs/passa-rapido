PASSA RÁPIDO
Tempo de espera em serviços públicos, informado pelos próprios cidadãos
FIAP · Global Solution 2 · 2026 · CitizenTech

Aluno       Eduardo Andrade Martins Vasques · RM 556970 · 3SIOA
Repositório https://github.com/eamvzs/passa-rapido
Vídeos      ver ENTREGA-links.txt
Aplicativo  https://zesty-kleicha-7e66e7.netlify.app


1. PROBLEMA E PÚBLICO
---------------------
Quem depende de UPA, posto de saúde, Poupatempo, INSS ou CRAS sai de casa sem saber
quanto vai esperar. Para quem não pode perder um dia de trabalho, ou está doente, essa
incerteza custa tempo, dinheiro e saúde. Existem painéis de fila em algumas cidades,
cada um para um tipo de unidade. O Passa Rápido reúne todos os tipos em um só mapa.

Público: moradores de grandes cidades que usam serviço público presencial, em especial
famílias com crianças, idosos, pessoas com deficiência e quem tem pouco tempo livre.


2. ODS
------
ODS 3   Saúde e bem-estar. Mostra a espera em UPAs, pronto-socorros e UBS e indica a
        unidade mais rápida, reduzindo o tempo de pessoas doentes em fila.
ODS 11  Cidades e comunidades sustentáveis. Melhora o acesso aos serviços da cidade com
        participação da comunidade: quem informa a fila ajuda quem vem depois.
ODS 16  Instituições eficazes. Dá transparência ao atendimento (esperas, picos,
        avaliações) e mostra onde o serviço está sobrecarregado.


3. FUNCIONALIDADES
------------------
Principais
  1. Mapa em tempo real      Unidades coloridas pela espera; atualiza sem recarregar
                             (Supabase Realtime). Busca, filtro por tipo e por serviço.
  2. Registro de fila        "Cheguei", "Fui atendido", "Saí": o banco calcula a espera
                             real. Sugere o registro quando a pessoa está a menos de 150 m.
  3. Melhor horário          Espera média por hora e dia da semana, mapa de calor da
                             semana e melhor janela.
  4. Mais rápido agora       Soma deslocamento e espera e indica a melhor unidade.

Complementares
  - Alerta de fila baixa, avisos da comunidade, avaliações, pontos e confiabilidade.
  - Ficha em quatro abas (Agora, Ir, Sobre, Opiniões): o que levar, aviso de feriado,
    plano de ida, comparação com unidades vizinhas, rota por transporte público.
  - Acessibilidade física confirmada por quem já foi e texto sobre atendimento prioritário.
  - Triagem informativa (192, UPA ou UBS). Não é diagnóstico e precisa de revisão
    de profissional de saúde antes de uso real.
  - Modo econômico (lista sem mapa), última lista salva quando a internet cai, leitura
    em voz, alto contraste, letras maiores, tema claro e escuro.
  - Denúncia de conteúdo, moderação, correção de localização por consenso.
  - Painel da cidade e visão por bairro para a gestão, com exportação em CSV.
  - Porta de entrada para dado oficial de espera enviado por um órgão conveniado.
  - LGPD: termos, política de privacidade, nome público abreviado, exclusão de conta.


4. TECNOLOGIAS E JUSTIFICATIVAS
-------------------------------
Flutter     Uma base de código para web e Android; permitiu testar o app inteiro no
            navegador. O edital aceita Flutter.
Supabase    PostgreSQL com autenticação, segurança por linha e tempo real, sem servidor
            próprio.
PL/pgSQL    As regras de negócio (cálculo da espera, pontos, alertas, limites, moderação)
            ficam em procedures, funções e gatilhos no banco, então valem para qualquer
            cliente e o app não grava pontos, peso nem hora de chegada.

PL/SQL: o edital cita PL/SQL (Oracle). O banco do projeto é PostgreSQL, cuja linguagem
procedural é o PL/pgSQL, com os mesmos recursos (blocos, cursores, exceções, funções,
procedures e gatilhos) e sintaxe muito próxima. O tutor confirmou que atende.

Detalhes em docs/tecnologias-e-beneficios.md e docs/gerenciamento-de-memoria-e-eficiencia.md.


5. COMO EXECUTAR (Windows)
--------------------------
Pré-requisitos
  - Flutter 3.50 ou mais novo (flutter --version) e Google Chrome ou Edge.
  - Android Studio só para emulador ou celular Android. O aviso do Visual Studio no
    "flutter doctor" pode ser ignorado.

Rodar o aplicativo (já aponta para um projeto Supabase de demonstração)
    cd app
    flutter pub get
    flutter run -d chrome
  Aceite a permissão de localização. Sem ela, o app usa o centro de São Paulo.

Usar o seu próprio Supabase
  1. Crie um projeto em supabase.com e, no SQL Editor, cole database/supabase_instalar.sql
     inteiro e clique em Run. Um banco que já tem os scripts 01 a 06 usa
     database/supabase_atualizar.sql. Ambos podem ser repetidos sem prejuízo.
  2. Em Authentication, desligue "Confirm email" (testes) e informe a Site URL.
  3. Rode com a chave PÚBLICA (anon/publishable). A chave secreta nunca vai no app:
       flutter run -d chrome --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co
                             --dart-define=SUPABASE_KEY=SUA_CHAVE_PUBLICA
  4. Unidades reais de São Paulo (CNES e OpenStreetMap): database/LEIA-ME-DADOS-REAIS.txt.
  5. Moderação, dado oficial e ajustes: database/LEIA-ME-14.txt.

Versão web para publicar
    cd app
    flutter build web --release --no-web-resources-cdn
  Publicar o conteúdo de app/build/web em qualquer hospedagem HTTPS (inclui o arquivo
  _headers com os cabeçalhos de segurança, lido pela Netlify).

Testes
    cd app && flutter test                                    72 testes
    bash app/tool/teste_importador/rodar.sh                   importadores (servidor falso)
    cd database && ./recriar_local.sh passa_rapido            banco local (PostgreSQL)
    psql -U postgres -v ON_ERROR_STOP=1 -d passa_rapido -f tests/test_rotinas.sql
    (idem test_regras_09.sql e test_sugestoes_13.sql)
    ./tests/rodar_supabase_local.sh ...  e  tests/test_melhorias_14.sql   (ver LEIA-ME-14)
    ./app/test_e2e/rodar.sh                                   6 roteiros no navegador
  Resumo dos resultados: docs/qualidade-e-testes.md.


6. ESTRUTURA DO REPOSITÓRIO
---------------------------
  app/             aplicativo Flutter
    lib/core       regras puras (níveis, previsão, triagem, feriados, tema...)
    lib/models     classes que leem as linhas do banco
    lib/data       acesso ao Supabase e à localização
    lib/state      controladores de estado (provider)
    lib/ui         telas e componentes
    test/          testes de unidade     test_e2e/  roteiros no navegador
    tool/          importadores de unidades (OpenStreetMap e CNES)
  database/        scripts SQL numerados, testes e pacotes prontos para o Supabase
  docs/            documentação (lista abaixo)

  docs/modelo-de-dados.md                       MER, DER, tabelas, restrições, rotinas
  docs/descricao-de-classes-e-metodos.md        classes, métodos e rotinas do banco
  docs/gerenciamento-de-memoria-e-eficiencia.md práticas aplicadas e limites
  docs/tecnologias-e-beneficios.md              escolhas, benefícios, riscos, identidade visual
  docs/seguranca-e-privacidade.md               modelo de segurança e LGPD
  docs/qualidade-e-testes.md                    testes executados e defeitos encontrados
  docs/operacao.md                              publicação, backup, monitoramento, dados abertos
  docs/pesquisa-de-mercado.md                   soluções existentes e o que o app aproveita
  docs/roadmap.md                               o que não foi feito e próximos passos
  docs/atendimento-ao-edital.md                 requisitos do edital e onde estão
  docs/videos/                                  roteiros dos pitches
  docs/telas/, der.png, mer.png                 capturas e diagramas


7. LIMITES CONHECIDOS
---------------------
  - Não existe fonte pública de fila em tempo real para esses serviços. A fila ao vivo vem
    de quem usa o app e começa vazia; sem registro, a tela mostra uma estimativa do modelo
    (marcada com "~" e "est."), nunca como dado real.
  - UBS, UPA e pronto-socorro vêm do CNES/DATASUS. INSS, Poupatempo e CRAS vêm do
    OpenStreetMap, com cobertura parcial. Horários são os padrões de cada tipo de unidade.
  - Sem notificação com o app fechado (exige Firebase e conta Apple Developer) e sem canal
    de WhatsApp.
  - APK Android não gerado. Safari/iPhone e Android reais não foram testados.
  - Recuperação de senha por e-mail e leitura em voz em aparelho real não foram verificadas.
  - O app carrega todas as unidades de uma cidade de uma vez; para o país seria preciso
    consultar por região do mapa.
  - Triagem e textos jurídicos ainda não passaram por profissional de saúde nem de direito.
  Lista completa em docs/roadmap.md.


8. CRÉDITOS
-----------
  Mapa, INSS, Poupatempo, CRAS: © colaboradores do OpenStreetMap (ODbL).
  Unidades de saúde: CNES/DATASUS, Ministério da Saúde (dados abertos).
  Fonte Plus Jakarta Sans: SIL Open Font License 1.1 (app/assets/fonts).
  Pacotes: provider, supabase_flutter, flutter_map, latlong2, geolocator, fl_chart,
  flutter_tts, shared_preferences, url_launcher (versões em app/pubspec.lock).
