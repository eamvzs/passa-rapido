# Pitch técnico (até 5 minutos, vale nota)

YouTube como **não listado**. Tela do notebook com narração. Alvo: 4 min 40 s. O vídeo percorre os requisitos do edital, nesta ordem.

## Antes de gravar

- Feche notificações e abas pessoais. Resolução 1920×1080; zoom do navegador em 125% e do editor com Ctrl +, para o texto ficar legível.
- Deixe abertos, em ordem: README.txt, app no navegador (duas janelas lado a lado), docs/mer.png e der.png, database/02_funcoes.sql e 03_triggers.sql, docs/seguranca-e-privacidade.md, docs/qualidade-e-testes.md, docs/atendimento-ao-edital.md e o GitHub.
- Rode antes, para ver se está tudo verde: flutter test (na pasta app). O resultado ao vivo leva tempo; grave e acelere esse trecho na edição.
- Faça um registro de teste (Cheguei, Fui atendido) antes de gravar, para saber qual unidade usar e onde clicar.
- Ensaie uma vez lendo em voz alta com cronômetro. O texto leva cerca de 3 min 45 s sem ação na tela; com os cliques, fica perto de 4 min 40 s.

## Cenas

### 1. Abertura (0:00 a 0:30)

**Na tela:** README.txt aberto no editor e a árvore de pastas (app, database, docs). Câmera desligada.

> Olá, eu sou o Eduardo Vasques, RM 556970, turma 3SIOA. Este é o Passa Rápido, minha solução para o tema CitizenTech: um mapa com o tempo de espera em UPA, UBS, Poupatempo, INSS e CRAS. O app é em Flutter, o banco é o Supabase, que é PostgreSQL com login e tempo real, e as regras de negócio ficam dentro do banco, em PL/pgSQL. Vou mostrar o app, o modelo de dados, as rotinas, a segurança e os testes.

### 2. O app funcionando (0:30 a 1:35)

**Na tela:** Navegador com o app aberto no mapa. Segunda janela do app ao lado, para mostrar o tempo real.

> Primeiro o mapa em tempo real. As unidades vêm de uma view do banco e são coloridas pela espera, com busca e filtros por tipo e serviço. Aqui eu toco em Cheguei na fila e depois em Fui atendido: quem calcula a espera real é o banco. Olhem a segunda janela: o número mudou sozinho, é o Supabase Realtime. Na ficha, o melhor horário mostra a espera média por hora e o mapa de calor da semana. A aba Rápido soma deslocamento e espera. Para quem mais precisa, a ficha traz acessibilidade confirmada por quem já foi, o que levar e o direito a atendimento prioritário. Também há modo econômico e uma triagem informativa entre 192, UPA e UBS.

### 3. Acessibilidade e privacidade (1:35 a 2:10)

**Na tela:** Perfil: tema escuro, alto contraste, letras maiores. Depois alargue a janela para mostrar o menu lateral.

> Tema claro e escuro, alto contraste, letras maiores e menu lateral em tela larga. O contraste das cores é conferido por teste automático, no mínimo 4,5 para 1. Há leitura em voz, e as rotas têm URL, então o botão voltar do navegador funciona. Na privacidade: termos, política, aceite no cadastro e exclusão de conta.

### 4. Modelo de dados e PL/pgSQL (2:10 a 3:00)

**Na tela:** docs/mer.png e docs/der.png; depois o arquivo database/02_funcoes.sql e o 03_triggers.sql, rolando devagar.

> O modelo relacional tem 22 tabelas, todas com segurança por linha. As rotinas estão em PL/pgSQL, o equivalente do PL/SQL no PostgreSQL, e o tutor confirmou que atende. A prc_recalcular_situacao calcula a espera por média ponderada dos últimos registros, com peso do usuário e decaimento no tempo. A prc_expirar_registros usa cursor e trata exceção por unidade. A prc_consolidar_historico agrega por dia e hora para a previsão. Gatilhos atualizam pontos, nível e confiabilidade, e o pg_cron agenda as rotinas.

### 5. Segurança (3:00 a 3:35)

**Na tela:** docs/seguranca-e-privacidade.md na tela, ou o terminal com a saída dos testes de segurança.

> A chave do app é pública, então a segurança está no banco: segurança por linha, permissões por coluna e gatilhos. Fiz uma revisão com ataques simulados: registrar em nome de outro usuário, forjar hora de chegada e pontos, virar moderador pelo app. Tudo bloqueado. A revisão também achou um problema real: o identificador de quem escreve avisos era público, o que permitiria seguir uma pessoa por várias unidades. Corrigi, e o site roda com política de segurança de conteúdo.

### 6. Testes (3:35 a 4:05)

**Na tela:** Terminal com 'flutter test' terminando em 72 testes passando; depois docs/qualidade-e-testes.md.

> No banco, são 19 verificações das rotinas, 21 das regras de segurança, 18 das sugestões e 69 das melhorias de acessibilidade, denúncia, moderação e permissões. No Flutter, 72 testes. No navegador, seis roteiros com Playwright que rodam com um comando.

### 7. Documentação e limites (4:05 a 4:40)

**Na tela:** Pasta docs/ aberta; depois docs/atendimento-ao-edital.md.

> A documentação traz a descrição de classes e métodos, memória e eficiência, tecnologias e benefícios, o modelo de dados e o README com instruções. E os limites, com honestidade: a fila ao vivo depende dos cidadãos e, sem registro, o app mostra uma estimativa identificada como tal. INSS, Poupatempo e CRAS vêm do OpenStreetMap, com cobertura parcial. Não há notificação com o app fechado, a triagem ainda precisa de revisão de profissional de saúde e o APK não foi gerado.

### 8. Fechamento (4:40 a 4:50)

**Na tela:** Página do repositório no GitHub (github.com/eamvzs/passa-rapido).

> Código e documentação estão no GitHub, no link da entrega. Obrigado!

## Depois de gravar

- Corte pausas e erros; acelere só a execução do flutter test. Mantenha o vídeo final abaixo de 5:00.
- Confira se o código e os números aparecem com tamanho legível no vídeo exportado (MP4, 1080p).
- YouTube: visibilidade “Não listado”. Abra o link em janela anônima e veja o vídeo inteiro antes de colar no ENTREGA-links.txt.

## Cuidados

- Não diga que existe APK nem que o app foi testado em iPhone ou Android.
- Diga PL/pgSQL e explique que é o equivalente do PL/SQL no PostgreSQL; o tutor confirmou.
- Use só os números dos documentos (22 tabelas, 72 testes, 19/21/18/69 no banco, 6 roteiros).
- Não prometa fila ao vivo em todas as unidades: ela depende de quem usa.
