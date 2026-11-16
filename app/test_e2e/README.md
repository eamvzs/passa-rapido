# Testes de ponta a ponta (navegador)

Seis roteiros Playwright que abrem o site compilado em um navegador real (celular 412×870) e conferem o que a
pessoa vê e faz. Cobrem as melhorias de serviço público: ajuda, modo econômico, triagem, ficha com acessibilidade e
feriado, plano de ida, denúncia, moderação, visão da gestão, pergunta de fila por presença, ponto de partida,
modo sem internet, cabeçalhos de segurança (CSP), XSS e rotas malformadas.

| Arquivo | O que testa |
|---|---|
| `01_ajuda_economico_triagem.js` | Ajuda, modo econômico (zero requisições de mapa), triagem (UBS, UPA, 192) |
| `02_ficha_visitante.js` | Feriado, "o que levar", acessibilidade, comentário oculto, escolha do modo de transporte |
| `03_logado_moderacao_gestao.js` | Sessão simulada: "Sua semana", moderação, voto, denúncia, plano de ida, tabela da gestão com CSV seguro |
| `04_presenca_referencia_offline.js` | Pergunta "como está a fila?" (relógio simulado), toque longo no mapa, ajuda, modo sem internet |
| `05_csp.js` | O app funciona sob a política de segurança de conteúdo (sem violações) |
| `06_xss_e_rotas.js` | Texto malicioso não executa, CSP bloqueia script inline, rotas inválidas não derrubam o app |

`mock.js` simula as respostas do Supabase para o que exige conta ou o script 14; o que é público (lista de unidades)
vem do Supabase real. `servir.js` serve `build/web` aplicando o arquivo `_headers`, como a Netlify.

Rodar: `./rodar.sh` (veja o cabeçalho do script).
