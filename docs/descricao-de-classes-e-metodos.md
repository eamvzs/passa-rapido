# Descrição de classes, métodos e rotinas

Caminhos relativos a `app/lib` (aplicativo) e `database/` (banco).

## 1. Aplicativo

### Arquitetura
`ui` (telas) lê de `state` (controladores com `ChangeNotifier`, via `provider`), que usa `data` (repositórios do Supabase) e
`models` (classes que leem as linhas). `core` guarda as regras puras, sem Flutter nem rede, por isso testáveis em unidade.

### `main.dart` e `config/`
| Item | Descrição |
|---|---|
| `main()` | Inicia o Supabase, carrega as preferências e roda `PassaRapidoApp` |
| `PassaRapidoApp` | Registra os provedores, o tema e as rotas (`/unidade/<id>`, `/entrar`, `/termos`, `/privacidade`, `/nova-senha`) |
| `AppConfig` | Endereço e chave pública do Supabase e URL dos blocos do mapa, trocáveis com `--dart-define` |

### `core/`: regras puras
| Arquivo | Itens | Descrição |
|---|---|---|
| `nivel_espera.dart` | `NivelEspera`, `TamanhoFila` | Faixas de espera (até 15, 45, 90 min), cores e rótulos; percepção de fila informada |
| `previsao.dart` | `analisarMomento` | Compara a espera de agora com a típica da hora: "bom momento", "pico" ou "x% mais vazia/cheia que o normal" |
| `insights.dart` | `SlotSemanal`, `melhorEPiorJanela`, `resumirPorTipo`, `compararComVizinhas` | Melhor e pior janela da semana, espera média por tipo, comparação com unidades do mesmo tipo a até 5 km |
| `triagem.dart` | `avaliarTriagem` | Sinal de emergência indica 192; de urgência, UPA ou pronto-socorro; sem sinais, UBS |
| `feriados.dart` | `feriadosDoAno`, `feriadoDe`, `avisoDeFeriado` | Feriados fixos e os que dependem da Páscoa, mais os de São Paulo |
| `documentos.dart` | `oQueLevar` | Lista do que levar por tipo de unidade |
| `agendamento.dart` | `agendamentoDoTipo` | Link oficial para agendar (Poupatempo, Meu INSS, Meu SUS Digital) |
| `plano.dart` | `PlanoDeIda` | Hora de sair = horário marcado − deslocamento (20 km/h) − 15 min; grava e lê JSON |
| `presenca.dart` | `DetectorDePresenca` | Depois de 10 min a menos de 120 m de uma unidade aberta, indica perguntar a fila; silêncio de 3 h por unidade |
| `busca.dart` | `normalizarParaBusca`, `combinaComBusca` | Busca por palavras, sem acento e em qualquer ordem |
| `formatos.dart` | `formatarEspera`, `formatarDistancia`, `formatarHaQuantoTempo`, `campoCsv` | Texto de minutos, distância e tempo decorrido; campo de CSV protegido contra fórmula de planilha |
| `tema.dart` | `construirTema`, `PaletaVisual`, `IdentidadeVisual` | Tema claro e escuro montado a partir da paleta; cores do cartão de destaque |

### `models/`
| Classe | Descrição |
|---|---|
| `Unidade` | Linha de `vw_mapa_unidades`: situação, fonte (`tempo_real`, `oficial`, `historico`), `estimada`, `emTempoReal`, `comSituacao` (aplica um evento de tempo real) |
| `TipoUnidade`, `Servico`, `HorarioFuncionamento`, `PrevisaoHora`, `Recomendacao` | Dados de apoio; `proximaAbertura` devolve "Abre amanhã às 08:00" |
| `RegistroFila`, `Relato`, `Avaliacao`, `Favorito`, `Notificacao`, `Perfil`, `PosicaoRanking` | Dados da colaboração; `Perfil` calcula pontos para o próximo nível |
| `RecursoDeAcessibilidade`, `ContagemDeRecurso` | Votos de acessibilidade e o resumo "Confirmado por N pessoas" |
| `ImpactoSemanal`, `SugestaoPendente`, `DenunciaPendente`, `RegiaoDaGestao` | Resumo da semana, itens da moderação e linha da visão por região; `regioesParaCsv` exporta a visão |

### `data/`
| Classe | Descrição |
|---|---|
| `UnidadeRepositorio` | `listarMapa` (paginado, guarda cópia no aparelho e a usa sem conexão), tipos, serviços, horários, `melhorHorario`, `historicoSemanal`, `recomendar`, painel, indicadores, ranking, acessibilidade, visão por região |
| `FilaRepositorio` | Registrar fila, marcar atendimento, saída ou desistência, registro ativo e histórico |
| `ComunidadeRepositorio` | Avisos, avaliações, favoritos, notificações, sugestões, votos, denúncias, impacto, moderação, exclusão de conta |
| `LocalizacaoServico` | Posição única (`obter`) e acompanhamento (`acompanhar`); nunca lança erro, cai no centro de São Paulo |
| `traduzirErro` | Converte erros do Supabase e os códigos `PR001` a `PR014` do banco em mensagens para a pessoa |

### `state/`
| Controlador | Responsabilidade |
|---|---|
| `PreferenciasControlador` | Tema, alto contraste, letras maiores, modo econômico, apresentação vista |
| `SessaoControlador` | Login, cadastro, recuperação de senha, perfil, favoritos, notificações em tempo real |
| `MapaControlador` | Unidades, filtros, busca, ponto de referência, localização e canal de tempo real da situação |
| `FilaControlador` | Registro ativo: chegada, atendimento, saída, desistência |
| `PlanoControlador`, `NavegacaoControlador`, `PresencaControlador` | Plano de ida, aba atual, pergunta "como está a fila?" |

### `ui/`
| Item | Descrição |
|---|---|
| `AppShell` | Quatro abas (barra inferior ou lateral em tela larga), alertas e pergunta de fila |
| `MapaTela` | Mapa com pontos e melhores opções, lista "Perto/Rápido", busca, filtros, modo econômico, toque longo para outro ponto |
| `UnidadeDetalheTela` | Ficha em quatro abas fixas: Agora, Ir, Sobre, Opiniões; mapa de calor da semana, comparação, plano, acessibilidade |
| `RecomendacaoTela`, `TriagemTela` | Melhor opção agora e orientação por sinais de alerta |
| `PainelTela`, `GestaoTela` | Indicadores da cidade e visão por bairro e tipo (com CSV) |
| `PerfilTela`, `AjudaTela`, `ModeracaoTela` | Conta e preferências, ajuda em linguagem simples, fila de moderação (só para moderador) |
| `LoginTela`, `NovaSenhaTela`, `TermosTela`, `ApresentacaoTela` | Entrada, senha, termos e política, apresentação inicial |
| `componentes/comuns.dart` | `LogoPassaRapido`, `Secao`, `BlocoEspera`, `UnidadeCartao`, mensagens e estados vazio, erro e carregando |

## 2. Banco de dados (PL/pgSQL)

### Procedures
| Rotina | Script | Função |
|---|---|---|
| `prc_recalcular_situacao(unidade, momento)` | 02, 14 | Calcula a espera: leitura oficial recente, senão média ponderada dos registros das últimas 2 h (peso do usuário, decaimento no tempo), senão histórico |
| `prc_expirar_registros` | 02 | A cada 10 min: expira check-ins com mais de 6 h e recalcula cada unidade (cursor, erro isolado) |
| `prc_consolidar_historico` | 02 | Agrega registros em médias por unidade, dia e hora |
| `prc_completar_unidades_reais` | 08 | Completa serviços, horários e histórico das unidades importadas |
| `prc_analisar_sugestao` | 13 | Aceita ou recusa uma sugestão e aplica a correção |
| `prc_registrar_espera_oficial` | 14 | Grava leitura de órgão conveniado e recalcula |
| `prc_simular_movimento` | 02 | Gera movimento fictício para demonstração; não é agendada na instalação |

### Funções
| Grupo | Funções |
|---|---|
| Cálculo | `fn_minutos_por_tamanho`, `fn_tamanho_por_minutos`, `fn_indice_tamanho`, `fn_nivel_por_minutos`, `fn_nivel_por_pontos`, `fn_peso_usuario` |
| Tempo e lugar | `fn_distancia_km` (Haversine), `fn_dia_semana_local`, `fn_hora_local`, `fn_unidade_aberta` |
| Consulta | `fn_melhor_horario`, `fn_recomendar_unidades`, `fn_painel_geral`, `fn_meu_impacto`, `fn_resumo_dados_reais` |
| Colaboração | `fn_confirmar_relato`, `confirmar_relato`, `fn_nome_publico`, `excluir_minha_conta` |
| Configuração e identidade | `fn_config`, `fn_chamada_do_app`, `fn_usuario_atual` |
| Moderação | `fn_sou_moderador`, `fn_exigir_moderador`, `fn_listar_sugestoes_pendentes`, `fn_analisar_sugestao`, `fn_listar_denuncias_pendentes`, `fn_resolver_denuncia`, `fn_ocultar_conteudo` |
| Dado oficial | `fn_registrar_espera_oficial`, `fn_registrar_esperas_oficiais` (lote de até 500) |

### Gatilhos
| Gatilho | Efeito |
|---|---|
| `trg_registro_antes_inserir`, `_antes_atualizar`, `_depois`, `_confiabilidade` | Valida limites e localização, fixa chegada e peso, calcula espera real, recalcula a unidade e ajusta a confiabilidade de quem informou |
| `trg_relato_*`, `trg_avaliacao_*`, `trg_confirmacao_relato`, `trg_pontos_atualiza_usuario` | Limites, autor público, pontos e nível |
| `trg_situacao_alerta_favoritos` | Cria o alerta quando a espera cruza o limite do favorito |
| `trg_unidade_cria_situacao`, `trg_novo_usuario_auth` | Cria a situação da unidade e o perfil do usuário |
| `trg_sugestao_antes_inserir`, `trg_sugestao_consenso` | Limite de sugestões; três pessoas confiáveis a menos de 40 m corrigem a localização |
| `trg_denuncia_*`, `trg_avaliacao_oculta`, `trg_acessibilidade_voto` | Denúncia com ocultação automática, proteção da ocultação, limite de votos |

### Views
`vw_mapa_unidades`, `vw_indicadores_unidade`, `vw_ranking_colaboradores`, `vw_gestao_regiao`, `vw_acessibilidade_unidade`,
`vw_relato_publico`, `vw_avaliacao_publica`, `vw_sugestoes_resumo`.

### Códigos de erro
`PR001` a `PR014`: regras do negócio levantadas pelo banco (limite por hora, repetição, localização, confirmação própria,
login exigido, acesso restrito, denúncia inválida). O app as traduz em `traduzirErro`.
