# Qualidade e testes

## O que foi executado

| Frente | Como rodar | Resultado |
|---|---|---|
| Aplicativo (regras, modelos, tema) | `cd app && flutter test` | 72 testes passam, inclusive o contraste das cores em claro e escuro |
| Análise estática | `flutter analyze` | Sem erros nem avisos de código |
| Banco, rotinas | `database/tests/test_rotinas.sql` | 19 verificações |
| Banco, regras de segurança | `test_regras_09.sql` | 21 verificações |
| Banco, sugestões de correção | `test_sugestoes_13.sql` | 18 verificações |
| Banco, melhorias (RLS, permissões, moderação, denúncias, consenso) | `test_melhorias_14.sql`, em banco que imita o Supabase | 69 verificações |
| Importadores de unidades | `bash app/tool/teste_importador/rodar.sh` | Servidor falso do Overpass e do CNES |
| Navegador | `./app/test_e2e/rodar.sh` | 6 roteiros: ajuda, modo econômico, triagem, ficha, moderação, denúncia, plano, pergunta de fila, modo sem internet, CSP, XSS e rotas inválidas |

O pacote `database/supabase_atualizar.sql` foi aplicado duas vezes seguidas sem erro (idempotente). Os roteiros do navegador usam um
Supabase simulado para o que exige conta; a lista de unidades vem do Supabase real.

## Defeitos encontrados nos testes e corrigidos

| Defeito | Causa | Correção |
|---|---|---|
| Sem internet, o app caía em erro mesmo com cópia salva | Tipos e serviços eram carga obrigatória | Passaram a ser opcionais; os tipos são derivados das unidades |
| Avaliação denunciada não era ocultada | O gatilho de proteção tratava a rotina de moderação como o app | Decide por `current_user` |
| Abas da ficha rolavam para fora da tela | Faziam parte da lista | Cabeçalho fixo (`SliverPersistentHeader`) |
| Rótulo "Pronto-socorro" cortado no Painel | Coluna estreita | Coluna ampliada |
| Marcadores numerados sem significado para quem usa | Agrupamento por proximidade | Pontos coloridos e etiqueta só nas melhores opções da área visível |
| CNES trazia só 46 unidades | A paginação da API conta páginas, não registros | O importador detecta o modo sozinho |
| Unidades de saúde duplicadas entre CNES e OpenStreetMap, e coordenadas erradas do CNES | Fontes diferentes | `12_deduplicar_osm_cnes.sql` |
| Dois estilos visuais reprovaram no contraste | Início do degradê claro demais | Escurecido; hoje só há uma identidade |

## Não verificado

- Safari e Android reais, GPS real, leitor de tela real, APK.
- Recuperação de senha por e-mail e leitura em voz em aparelho.
- Telas que dependem de conta foram testadas com Supabase simulado e com o banco local, não com contas reais no Supabase de produção.
- Triagem sem revisão de profissional de saúde; termos e política sem revisão jurídica.
