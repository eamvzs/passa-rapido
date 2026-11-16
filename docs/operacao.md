# Operação

## Publicar o site
1. `cd app && flutter build web --release --no-web-resources-cdn`.
2. Publicar o conteúdo de `app/build/web` (precisa ter `index.html` na raiz e o arquivo `_headers`) em uma hospedagem HTTPS.
   Na Netlify: Deploys, arrastar a pasta.
3. No Supabase, Authentication > URL Configuration: Site URL e Redirect URLs com o endereço publicado (necessário para
   "Esqueci minha senha").
4. Conferir em janela anônima, com Ctrl+F5: mapa, ficha, cadastro (senha de 8 caracteres ou mais), registrar uma fila.

Se `--dart-define=TILE_URL=...` trocar o provedor do mapa, incluir o endereço dele em `img-src` e `connect-src` do `_headers`.

## iPhone
Não há app nativo (exigiria Mac e Xcode). Abrir o site no Safari e usar Compartilhar > Adicionar à Tela de Início. A
localização só é liberada em páginas HTTPS.

## Banco de dados
- Instalação: `database/supabase_instalar.sql`. Atualização: `database/supabase_atualizar.sql`. Ambos repetíveis.
- Moderador: `insert into moderador (usuario_id) select id from auth.users where email = '...';`
- Dado oficial de um órgão conveniado e ajustes: `database/LEIA-ME-14.txt`. Importar unidades reais: `database/LEIA-ME-DADOS-REAIS.txt`.

## Backup e monitoramento (a configurar antes de ter usuários reais)
| Item | Como |
|---|---|
| Backup | Painel do Supabase > Database > Backups, e `pg_dump` semanal guardado criptografado em outro lugar; testar a restauração |
| Disponibilidade | Serviço externo de ping a cada 5 min |
| Rotinas agendadas | `select jobname, status, start_time from cron.job_run_details order by start_time desc limit 20;` |
| Fila de moderação | `select count(*) from sugestao_correcao where status = 'pendente';` |
| Dados parados | `select count(*) from situacao_unidade where atualizado_em < now() - interval '1 day';` |
| Incidente | Desligar cadastros (Auth) ou pausar o site; avaliar nos logs; corrigir; restaurar se preciso; comunicar titulares e ANPD; girar a chave de serviço se vazou |

## Dados abertos
O Supabase expõe, sem conta e em leitura, `vw_mapa_unidades`, `vw_gestao_regiao`, `vw_acessibilidade_unidade`,
`vw_relato_publico`, `vw_avaliacao_publica` e `rpc/fn_painel_geral`. Exemplo:

```bash
curl "$SUPABASE_URL/rest/v1/vw_gestao_regiao?select=*&tipo=eq.UPA" -H "apikey: $CHAVE_PUBLICA"
```

Sem registro de cidadãos, os números são estimativas do modelo (`fonte = 'historico'`).

## Capacidade
Acima de cerca de 5 000 unidades, passar a consultar por região do mapa. Para escala maior, transformar as visões que
calculam "aberta agora" em visões materializadas.
