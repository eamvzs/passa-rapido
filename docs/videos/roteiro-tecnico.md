# Pitch técnico (até 5 minutos, vale nota)

YouTube como **não listado**. Tela do notebook com narração. Alvo: 4 min 30 s; texto para ler em voz alta, sem improvisar. As falas entre parênteses e em itálico são ações na tela, não se leem. O vídeo percorre os requisitos do edital, nesta ordem.

## Antes de gravar

- Feche notificações e abas pessoais. Resolução 1920×1080; zoom do navegador em 125% e do editor com Ctrl +, para o texto ficar legível.
- Deixe abertos, em ordem: README.txt, app no navegador (duas janelas lado a lado), docs/mer.png e der.png, database/02_funcoes.sql e 03_triggers.sql, docs/seguranca-e-privacidade.md, docs/qualidade-e-testes.md, docs/atendimento-ao-edital.md e o GitHub.
- Rode antes, para ver se está tudo verde: flutter test (na pasta app). O resultado ao vivo leva tempo; grave e acelere esse trecho na edição.
- Faça um registro de teste (Cheguei, Fui atendido) antes de gravar, para saber qual unidade usar e onde clicar.
- Ensaie uma vez lendo em voz alta com cronômetro. Leia em ritmo normal, sem correr: o texto leva uns 4 minutos e 30 segundos com os cliques.

## Cenas

### 1. Abertura (0:00 a 0:30)

**Na tela:** README.txt aberto e a árvore de pastas (app, database, docs).

> Oi, eu sou o Eduardo Vasques, RM 556970, da turma 3SIOA. Esse é o Passa Rápido, meu projeto da Global Solution. Quem vai numa UPA, num posto ou no INSS quase nunca sabe quanto vai esperar, e o app mostra isso num mapa só. Fiz em Flutter, com o banco no Supabase, e as regras de negócio ficam dentro do banco, em PL/pgSQL. Vou mostrar o app e depois a parte técnica.

### 2. O mapa e o registro de fila (0:30 a 1:20)

**Na tela:** App aberto no mapa. Segunda janela do app ao lado, só para mostrar a atualização.

> Esse é o mapa. Cada ponto é uma unidade, e a cor mostra a fila: verde é baixa, amarelo moderada, até o vermelho. Dá para buscar e filtrar por tipo. *(Clique numa unidade.)* Na ficha eu vejo a espera de agora, e o Melhor horário mostra a espera média por hora e um mapa de calor da semana. *(Clique em Cheguei na fila.)* Agora eu registro que cheguei. *(Olhe a segunda janela.)* Olha aqui na outra janela: o número mudou sozinho, sem recarregar. Isso é o Realtime do Supabase. *(Clique em Fui atendido.)* E quando eu marco que fui atendido, quem calcula a espera real é o banco, não o aplicativo.

### 3. Rápido, acessibilidade e triagem (1:20 a 1:50)

**Na tela:** Aba Rápido; depois a ficha: o que levar e acessibilidade; modo econômico no Perfil.

> Na aba Rápido, o app soma o tempo de deslocamento com a espera e mostra a unidade que sai mais rápida agora. Muitas vezes a mais perto não é a melhor. *(Abra uma ficha.)* Na ficha tem o que levar e a acessibilidade, como rampa e elevador, confirmada por quem já foi. Tem o modo econômico, só com a lista, para internet fraca, e uma triagem informativa entre 192, UPA e UBS, que não faz diagnóstico.

### 4. Acessibilidade e privacidade (1:50 a 2:10)

**Na tela:** Perfil: tema escuro, alto contraste e letras maiores. Depois aumente a largura da janela para aparecer o menu lateral.

> No Perfil dá para trocar o tema, ligar o alto contraste e aumentar as letras. O contraste é conferido por teste automático, com mínimo de 4,5 para 1. Em tela larga aparece um menu lateral, e tem leitura em voz e exclusão de conta.

### 5. Modelo de dados e PL/pgSQL (2:10 a 2:55)

**Na tela:** docs/mer.png e docs/der.png; depois database/02_funcoes.sql e 03_triggers.sql, rolando devagar.

> Agora o banco. Aqui estão o MER e o DER: são 22 tabelas, todas com segurança por linha. As rotinas são em PL/pgSQL, o equivalente do PL/SQL no PostgreSQL, e o tutor confirmou que atende. A prc_recalcular_situacao calcula a espera de cada unidade com uma média ponderada dos últimos registros, com peso do usuário e queda do peso com o tempo. A prc_expirar_registros usa um cursor. A prc_consolidar_historico agrupa por dia e hora e alimenta o melhor horário. Gatilhos atualizam pontos e confiabilidade, e o pg_cron agenda tudo.

### 6. Segurança (2:55 a 3:20)

**Na tela:** docs/seguranca-e-privacidade.md na tela.

> A chave do app é pública, então a segurança tem que estar no banco: segurança por linha, permissão por coluna e gatilhos. Eu simulei ataques, como registrar em nome de outra pessoa, forjar hora e pontos, ou virar moderador pelo app. Tudo foi bloqueado. A revisão também achou um problema real: o identificador de quem escreve avisos era público e permitia seguir uma pessoa entre unidades. Eu corrigi.

### 7. Testes (3:20 a 3:45)

**Na tela:** Terminal com flutter test terminando em 72 testes passando; depois docs/qualidade-e-testes.md.

> Sobre testes: no banco são 19 verificações das rotinas, 21 da segurança, 18 das sugestões e 69 das melhorias mais recentes. No Flutter são 72 testes, que aparecem aqui passando, e seis roteiros no navegador, com Playwright.

### 8. Documentação e limites (3:45 a 4:15)

**Na tela:** Pasta docs/ aberta; depois docs/atendimento-ao-edital.md.

> A documentação está na pasta docs: classes e métodos, memória e eficiência, tecnologias e modelo de dados. Sobre os limites: a fila ao vivo depende de quem usa o app, então começa vazia, e sem registro o app mostra uma estimativa marcada como tal. INSS, Poupatempo e CRAS têm cobertura parcial. Não há notificação com o app fechado, a triagem precisa de revisão de um profissional de saúde e o APK não foi gerado.

### 9. Fechamento (4:15 a 4:25)

**Na tela:** Página do repositório no GitHub (github.com/eamvzs/passa-rapido).

> O código e a documentação estão no GitHub, no link da entrega. Obrigado!

## Depois de gravar

- Corte pausas e erros; acelere só a execução do flutter test. Mantenha o vídeo final abaixo de 5:00.
- Confira se o código e os números aparecem com tamanho legível no vídeo exportado (MP4, 1080p).
- YouTube: visibilidade “Não listado”. Abra o link em janela anônima e veja o vídeo inteiro antes de colar no ENTREGA-links.txt.

## Cuidados

- Não diga que existe APK nem que o app foi testado em iPhone ou Android.
- Diga PL/pgSQL e explique que é o equivalente do PL/SQL no PostgreSQL; o tutor confirmou.
- Use só os números dos documentos (22 tabelas, 72 testes, 19/21/18/69 no banco, 6 roteiros).
- Não prometa fila ao vivo em todas as unidades: ela depende de quem usa.
