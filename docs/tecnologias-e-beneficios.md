# Tecnologias e benefícios

Versões em `app/pubspec.lock` (Flutter 3.50, Dart 3.14).

## Aplicativo

| Tecnologia | Para que serve | Benefício | Custo ou risco |
|---|---|---|---|
| Flutter / Dart | Interface única para web e Android (o edital aceita Flutter) | Um código só; todo o app foi verificado no navegador | Pacote web grande no primeiro carregamento |
| provider 6.1.5 | Estado com `ChangeNotifier` e `context.select` | Poucos controladores e telas que reconstroem só o que mudou | Menos estrutura que soluções maiores (Riverpod, Bloc) |
| supabase_flutter 2.18 | Login, consultas, funções do banco e tempo real | Uma dependência para todo o backend | Depende do Supabase |
| flutter_map 8.3 + latlong2 | Mapa e distâncias; blocos do OpenStreetMap | Sem chave de API nem cobrança; mapa escuro no tema escuro | O servidor público não é para tráfego intenso: em produção, trocar por provedor contratado (`--dart-define=TILE_URL`) |
| geolocator 14 | Localização do aparelho | Distância, ordenação "Perto", recomendação, check-in por proximidade | Exige permissão; sem ela o app usa o centro de São Paulo |
| fl_chart 1.3 | Gráfico de espera por hora | Sem web view | Mais um pacote; o gráfico tem descrição em texto |
| flutter_tts 4.2 | Leitura em voz (pt-BR) | Acessibilidade sem serviço pago | Voz depende do aparelho |
| shared_preferences 2.5 | Preferências, plano de ida e última lista de unidades | Funciona sem internet | Só valores simples |
| url_launcher 6.3 | Abre rota, telefone e agendamento | Rota por transporte público, a pé, carro ou bicicleta | |
| Plus Jakarta Sans | Fonte do app, empacotada em `assets/fonts` | Sem download em tempo de execução (licença SIL OFL) | |

## Banco e backend

| Tecnologia | Para que serve | Benefício | Custo ou risco |
|---|---|---|---|
| PostgreSQL + PL/pgSQL | Regras de negócio em procedures, funções e gatilhos | Valem para qualquer cliente; o app não grava pontos, peso nem hora de chegada | O edital cita PL/SQL (Oracle); a linguagem é a equivalente do PostgreSQL |
| Supabase | PostgreSQL com autenticação, segurança por linha e tempo real | Sem servidor próprio; demonstração com dois aparelhos | Limites do plano gratuito; backups a configurar |
| Segurança por linha (RLS) | Controle de acesso dentro do banco | A chave pública do app não dá acesso indevido; verificado por testes | Regras precisam de teste a cada mudança |
| Realtime | Envia mudanças ao app | O mapa muda quando alguém informa a fila | O canal não é filtrado por cidade |
| pg_cron | Agenda rotinas no banco | Expira check-ins esquecidos e consolida o histórico | Extensão a ativar no Supabase |

## Dados e ferramentas

| Tecnologia | Para que serve | Benefício | Custo ou risco |
|---|---|---|---|
| CNES / DATASUS | Cadastro oficial de UBS, UPAs e prontos-socorros | Dado oficial e completo | Coordenadas às vezes erradas; sem horário de funcionamento |
| OpenStreetMap + Overpass | INSS, Poupatempo e CRAS | Aberto e gratuito | Cobertura parcial e editável por qualquer pessoa |
| Importadores em Dart (`app/tool`) | Geram o SQL de carga, repetível | Nada a instalar além do Flutter | |
| Playwright | Roteiros de teste no navegador (`app/test_e2e`) | Repetíveis com um comando | |

## Identidade visual

Estilo institucional moderno: azul-marinho (`#1B3A6B`) com detalhe verde-menta, fundo neutro, cartões de 16 px de raio e
botões de 12 px, fonte Plus Jakarta Sans, tema claro e escuro. A cor da marca fica fora da escala verde, amarelo, laranja e
vermelho das filas, que tem significado fixo. O contraste (mínimo de 4,5 para 1) é conferido por teste automático
(`app/test/tema_test.dart`). A paleta fica em `app/lib/core/tema.dart` e a logo em `docs/marca/logo-icone.svg`.
