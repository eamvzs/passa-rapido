# Roadmap e limites

## O que já está pronto
Mapa em tempo real, registro de fila, previsão, recomendação, alertas, avisos, avaliações, pontos, ficha em quatro abas
(o que levar, plano de ida, comparação, acessibilidade, rota por transporte público), triagem informativa, modo econômico e
cópia offline, moderação, denúncia, visão para a gestão e entrada de dado oficial. Detalhes em `descricao-de-classes-e-metodos.md`.

## Limites atuais
| Limite | Observação |
|---|---|
| Fila ao vivo depende de cidadãos | Sem registro, o app mostra estimativa do modelo, marcada como tal |
| INSS, Poupatempo e CRAS com cobertura parcial | Vêm do OpenStreetMap; horários são os padrões do tipo |
| Sem APK; Safari e Android reais sem teste | Versão web verificada no navegador |
| Triagem sem revisão clínica; termos sem revisão jurídica | Obrigatório antes de uso real |
| Rotinas em PL/pgSQL (PostgreSQL), não em PL/SQL (Oracle) | Confirmação do tutor pendente |
| Sem notificação com o app fechado, sem WhatsApp | Exigem Firebase, conta Apple Developer e provedor de mensagens |
| Sem Libras em vídeo, sem portabilidade de dados | Previstos |

## Próximos passos, por prioridade
1. Piloto em uma região, com divulgação local, para gerar os primeiros registros reais.
2. Convênio com um órgão para alimentar `espera_oficial` (a entrada já existe).
3. Revisão clínica da triagem e revisão jurídica dos termos; encarregado de dados.
4. Ligar "Confirm email" com e-mail próprio (SMTP), `validar_localizacao` e backups.
5. Notificação com o app fechado e canal de WhatsApp ou SMS.
6. Provedor de mapa contratado; consulta por região do mapa para escalar além de uma cidade.
7. Reduzir a precisão da coordenada gravada e criar exportação dos dados do usuário.
8. Porte das rotinas para Oracle PL/SQL, se o tutor exigir.
