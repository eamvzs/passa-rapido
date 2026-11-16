# Gerenciamento de memória e eficiência

O que o código faz hoje, com o arquivo onde está. Não houve medição de memória, quadros por segundo ou bateria em
aparelho real; o que segue são decisões de projeto, mais as duas medições pontuais da seção 5.

## 1. Liberação de recursos

Tudo que segura um recurso é liberado quando a tela ou o controlador sai de cena.

| Recurso | Onde | Como |
|---|---|---|
| Controladores de texto e do mapa | `mapa_tela.dart`, `login_tela.dart`, `nova_senha_tela.dart`, formulários da ficha | `dispose()` de cada um |
| Voz (`FlutterTts`) | `unidade_detalhe_tela.dart` | `dispose` para a fala ao sair da ficha |
| Fluxo de GPS e de login | `controladores.dart` | `StreamSubscription.cancel()` no `dispose` |
| Canais de tempo real | `controladores.dart` | `removeChannel` ao descartar o controlador e ao trocar de usuário; o canal de notificações filtra por `usuario_id` |
| Relógio da pergunta de fila | `PresencaControlador` | `Timer.cancel()` no `dispose` |

## 2. Telas e listas

| Prática | Efeito |
|---|---|
| Lista de unidades preguiçosa (`SliverList.separated`) e ficha em `CustomScrollView` | Só o que está perto da janela vira widget |
| `const` em widgets e `context.select` onde só um campo importa | Reconstrução mínima |
| Abas da ficha: só a aba aberta é montada | Menos widgets por tela |
| Marcadores: pontos simples no zoom afastado e etiqueta só para as 6 melhores opções da área visível | Menos widgets sobre o mapa e mapa legível |
| Modo econômico (lista sem mapa) | Não baixa blocos de mapa |
| Evento de tempo real troca só a unidade afetada (`comSituacao`) | Sem recarregar a lista |
| `IndexedStack` nas quatro abas principais | Trocar de aba não reconstrói o mapa. Custo: as quatro ficam em memória |

## 3. Rede

| Prática | Efeito |
|---|---|
| Consultas em paralelo (`Future.wait`): mapa, perfil, painel e ficha; cada seção da ficha falha sem apagar as outras | Tempo total é o da consulta mais lenta |
| Lista de unidades paginada de 1000 em 1000 | Não corta resultados no limite da API |
| Última lista salva no aparelho | Sem internet, o app mostra a cópia com a hora |
| Tempo real em vez de consulta periódica | Sem tráfego parado |
| Cálculos no banco: views, funções, situação pré-calculada | O app recebe linhas prontas |
| Filtro por serviço só busca ao usar | |
| `limit` nas listas (10, 20, 30) | Respostas pequenas |
| GPS com `distanceFilter: 25` m e tempo limite de 8 s | Menos eventos; sem travar esperando sinal |
| Fonte empacotada | Nenhum download de fonte |

## 4. Banco

| Prática | Onde | Efeito |
|---|---|---|
| Índices parciais (`where ativo`, `where status = 'aguardando'`) e por data | `01_schema.sql` | Índices menores |
| Situação pré-calculada | `situacao_unidade` | O mapa lê uma linha por unidade |
| Histórico consolidado por unidade, dia e hora | `prc_consolidar_historico` | Previsão lê no máximo 24 linhas por dia |
| Janela de 2 horas no cálculo da espera | `prc_recalcular_situacao` | Custo limitado |
| Expiração de check-ins esquecidos e erro isolado por unidade (cursor) | `prc_expirar_registros` | Uma falha não interrompe o lote |
| Limites de uso por hora | script 09 | Evita volume anormal de um só usuário |

## 5. Medições

- Build web de produção: `main.dart.js` com cerca de 3,9 MB e `build/web` com cerca de 43 MB, dos quais 37 MB são do motor
  gráfico (`canvaskit`), que o navegador baixa em variantes.
- Lista de unidades visível em cerca de 2,1 s em um Chromium de teste, na mesma máquina do servidor (uma medição).

## 6. Limites e próximos passos

| Limite | Evolução |
|---|---|
| Todas as unidades de uma cidade são carregadas e o tempo real não é filtrado por cidade | Consultar por área visível e assinar por cidade |
| `vw_mapa_unidades` e `vw_gestao_regiao` recalculam "aberta agora" por linha | View materializada atualizada por `prc_expirar_registros` |
| A lista é recriada a cada evento de tempo real | Notificar só o item afetado |
| Quatro abas sempre em memória | Criar sob demanda, mantendo o mapa |
| Pacote web grande | WebAssembly e carregamento adiado |
