# Pesquisa de mercado

Levantamento em 15/11/2026 (busca na web). Parte das fontes é divulgação das próprias empresas ou reportagem: serve para mapear o
cenário, não como medição.

## Soluções existentes

| Solução | O que faz | Limite para o cidadão | O que o Passa Rápido aproveita |
|---|---|---|---|
| Painéis de prefeituras e estados (DF, Campo Grande, Jundiaí, Santo André) | Fila de UPAs em tempo real, com dado do sistema da unidade | Um painel por cidade e por tipo de unidade; sem mapa único | Reunir tipos e cidades em um mapa; aceitar dado oficial quando houver (`fn_registrar_espera_oficial`) |
| Menos Tempo (GovTech de Goiás) | Por WhatsApp, tempo total (deslocamento + fila) das unidades próximas; vende dado à gestão | Depende de contrato com o município | Aba "Mais rápido agora" e visão por região para a gestão |
| Meu SUS Digital | Agendamento em UBS, histórico e exames, com conta gov.br | Não mostra fila de quem chega sem agendamento; cobertura irregular | Link para agendar na ficha ("Antes de ir") |
| Poupatempo | Agendamento gratuito e serviços online; a central de monitoramento é interna | Sem fila ao vivo para o cidadão (não confirmado) | Link de agendamento; o app mostra a fila de quem vai sem agendar |
| Google Maps | Horários de pico e movimento ao vivo | Mede movimento, não espera de serviço público | Comparação "ao vivo × típico" e mapa de calor da semana |
| Waze | Dado vem dos usuários; pontos, níveis; usuários experientes editam o mapa | Foco em trânsito | Pontos, confiabilidade, correção colaborativa do cadastro |
| Apps de pronto-socorro no exterior (ER Wait Time, Urgence Québec) | Espera por hospital, distância, avaliações | Dependem do dado do hospital | Espera mais deslocamento, avaliação, alerta e transparência sobre o que é estimativa |
| QLess (fila virtual) | Posição na fila e aviso perto da vez | Exige integração com a unidade | Fora do alcance; inspirou o alerta de fila baixa |

## Decisões

Feito: link de agendamento, comparação com o horário típico, compartilhar unidade, sugestão de correção, acessibilidade, moderação,
visão para a gestão e porta de entrada para dado oficial. Fora do escopo desta entrega: canal de WhatsApp, fila virtual e
notificação com o app fechado (ver `roadmap.md`).

## Fontes

- Painéis de UPA: [Jornal de Brasília](https://jornaldebrasilia.com.br/brasilia/painel-mostra-em-tempo-real-filas-de-upas/), [Campo Grande News](https://www.campograndenews.com.br/cidades/capital/populacao-passa-a-ter-acesso-em-tempo-real-a-fila-de-espera-em-unidades-de-saude), [Tribuna de Jundiaí](https://tribunadejundiai.com.br/cidades/jundiai/upa-novo-horizonte-agora-tem-painel-de-tempo-de-espera-para-atendimento/), [DGABC (Santo André)](https://www.dgabc.com.br/Noticia/4351393/santo-andre-cria-sistema-para-consultar-espera-nas-upas)
- Menos Tempo (texto de divulgação): [Mais Goiás](https://www.maisgoias.com.br/cidades/startup-transforma-tempo-de-espera-no-sus-em-dado-estrategico-e-quer-expandir-modelo-no-pais/)
- Meu SUS Digital: [gov.br](https://www.gov.br/pt-br/apps/conecte-sus), [Canaltech](https://canaltech.com.br/apps/como-se-cadastrar-e-usar-o-app-meu-sus-digital/), [CONASS](https://www.conass.org.br/?p=52428)
- Poupatempo: [Tecnoblog](https://tecnoblog.net/responde/como-fazer-agendamento-online-no-poupatempo/), [Relatório 2024 (Prodesp)](https://www.prodesp.sp.gov.br/wp-content/uploads/2025/05/Relatorio-Resultados-do-Poupatempo-em-2024_compressed.pdf)
- Google Maps: [Ajuda do Google Maps](https://support.google.com/maps/answer/11323117?hl=en), [Blog do Google](https://blog.google/products/maps/maps101-popular-times-and-live-busyness-information/)
- Waze: [Harvard D3](https://d3.harvard.edu/platform-digit/submission/waze-leveraging-the-crowd-to-find-your-way/index.html), [Yu-kai Chou](https://yukaichou.com/gamification-examples/an-octalysis-look-at-the-waze-craze/)
- Apps de pronto-socorro: [ER Wait Time](https://apps.apple.com/us/app/-/id1477437465), [Urgence Québec](https://mwm.ai/apps/urgence-qubec/6751217896), [The Patient Wait](https://slashdot.org/software/comparison/Notable-vs-The-Patient-Wait/)
- Filas virtuais: [QLess](https://qless.com/what-is-a-virtual-queue-system-and-how-does-it-work), [QLess na App Store](https://apps.apple.com/us/app/-/id1033286225)
