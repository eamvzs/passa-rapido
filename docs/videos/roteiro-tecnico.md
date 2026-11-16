# Pitch técnico (até 5 minutos, vale nota)

YouTube como **não listado**. Meta: 4 min 30 s. O vídeo percorre os requisitos do edital, nesta ordem.

| Tempo | Tela | Fala |
|---|---|---|
| 0:00 a 0:25 | `README.txt` e pastas `app`, `database`, `docs` | "Este é o Passa Rápido, do tema CitizenTech: app em Flutter, com Supabase, que é PostgreSQL com login e tempo real, e a regra de negócio dentro do banco em PL/pgSQL. Vou mostrar o app, o modelo de dados, as rotinas do banco, os testes e a documentação." |
| 0:25 a 1:25 | App no navegador | "Mapa em tempo real: as unidades vêm de uma view do banco, coloridas pela espera, com busca e filtros. Registro colaborativo: 'Cheguei na fila' e 'Fui atendido'; o banco calcula a espera real. Com um segundo navegador aberto, o número muda sozinho: é o Supabase Realtime. Melhor horário: gráfico por hora e mapa de calor da semana. A aba Rápido soma deslocamento e espera. Para quem mais precisa do serviço, a ficha traz acessibilidade confirmada por quem já foi, o que levar e o direito a atendimento prioritário; há modo econômico e uma triagem informativa entre 192, UPA e UBS." |
| 1:25 a 2:05 | Tema escuro, alto contraste, janela larga | "Tema claro e escuro, alto contraste, letras maiores e menu lateral em tela larga. O contraste das cores é conferido por teste automático, mínimo de 4,5 para 1. Há leitura em voz, e as rotas têm URL, então o botão voltar do navegador funciona. Privacidade: termos, política, aceite no cadastro e exclusão de conta." |
| 2:05 a 2:50 | `docs/mer.png`, `docs/der.png`, `02_funcoes.sql`, `03_triggers.sql` | "Modelo relacional com 22 tabelas, todas com segurança por linha. As rotinas, em PL/pgSQL, que é o equivalente do PL/SQL no PostgreSQL: `prc_recalcular_situacao` calcula a espera por média ponderada dos últimos registros, com peso do usuário e decaimento no tempo; `prc_expirar_registros` usa cursor e trata exceção por unidade; `prc_consolidar_historico` agrega por dia e hora para a previsão. Gatilhos atualizam pontos, nível e confiabilidade, e o pg_cron agenda as rotinas." |
| 2:50 a 3:30 | Terminal ou `docs/seguranca-e-privacidade.md` | "A chave do app é pública, então a segurança está no banco: segurança por linha, permissões por coluna e gatilhos. Fiz uma revisão de segurança com ataques simulados: registrar em nome de outro usuário, forjar hora de chegada e pontos, virar moderador pelo app. Tudo bloqueado. A revisão achou problemas reais e os corrigiu, como o identificador de quem escreve avisos ser público, o que permitiria seguir uma pessoa por várias unidades de saúde. O site roda com política de segurança de conteúdo." |
| 3:30 a 4:05 | Terminal com os testes executados | "No banco: 19 verificações das rotinas, 21 das regras de segurança, 18 das sugestões e 69 das melhorias de acessibilidade, denúncia, moderação e permissões. No Flutter: 72 testes. No navegador, seis roteiros com Playwright que rodam com um comando." |
| 4:05 a 4:40 | `docs/` | "A documentação tem descrição de classes e métodos, memória e eficiência, tecnologias e benefícios, modelo de dados e README com instruções. Limites: a fila ao vivo depende de cidadãos e, sem registro, o app mostra estimativa identificada como tal; INSS, Poupatempo e CRAS vêm do OpenStreetMap com cobertura parcial; não há notificação com o app fechado; a triagem ainda precisa de revisão de profissional de saúde; o APK não foi gerado; e as rotinas são PL/pgSQL, não PL/SQL do Oracle." |
| 4:40 a 4:55 | Repositório no GitHub | "O código e a documentação estão no GitHub, no link da entrega. Obrigado!" |

Antes de gravar: app rodando com o Supabase atualizado, SQL Editor aberto, `der.png` e `mer.png` abertos, e `flutter test` e os testes
de banco já executados (mostre o resultado no terminal). Depois: abaixo de 5:00, texto de código legível, "Não listado", link em
`ENTREGA-links.txt`.

Cuidados: não dizer que o APK existe nem que foi testado em iPhone ou Android; chamar de PL/pgSQL e explicar a equivalência; usar só
números de `modelo-de-dados.md` e `qualidade-e-testes.md`.
