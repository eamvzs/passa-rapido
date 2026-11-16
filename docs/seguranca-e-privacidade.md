# Segurança e privacidade

Revisão feita em 15/11/2026 sobre o banco (scripts 01 a 14), o aplicativo web e o repositório, com consultas ao catálogo do
PostgreSQL, testes de ataque em banco que imita o Supabase e leitura de código. Não substitui auditoria independente nem
revisão jurídica.

## Modelo de segurança

O app usa só a chave pública do Supabase; por isso o controle de acesso está no banco.

- Todas as 22 tabelas têm segurança por linha (RLS). Visitante lê apenas dados públicos; cada usuário lê e grava só o que é seu.
- Pontos, peso, confiabilidade, hora de chegada e situação das unidades são calculados por gatilhos e procedures; o app não os grava.
- Rotinas internas e de moderação não são executáveis por visitante; moderação é conferida em cada chamada (`moderador`).
- Dado oficial de espera só entra por função liberada à chave de serviço.
- Limites por hora para registros, avisos, sugestões, votos e denúncias.
- O site é servido com política de segurança de conteúdo (CSP), `X-Frame-Options`, `nosniff`, `Referrer-Policy`,
  `Permissions-Policy` e HSTS (`app/web/_headers`).

## Achados e correções

| Achado | Risco | Correção |
|---|---|---|
| `usuario_id` de avisos e avaliações era público: dava para seguir uma pessoa por várias unidades de saúde | Médio (privacidade) | Leitura por `vw_relato_publico` e `vw_avaliacao_publica`, que só informam se o item é do próprio usuário |
| `TRUNCATE`, `REFERENCES`, `TRIGGER` e escrita em visões liberados ao visitante e ao app (padrão do Supabase) | Médio | Revogados em todas as tabelas e visões |
| Funções de gatilho e rotinas internas executáveis pelo app | Baixo | Revogadas |
| Exportação CSV do painel aceitava campo iniciado por `=`, `+`, `-` ou `@` (nomes vêm de base editável por qualquer pessoa) | Baixo | `campoCsv` protege o campo |
| Senha mínima de 6 caracteres | Baixo | App exige 8; a regra do servidor se ajusta em Authentication |
| Site sem cabeçalhos de segurança | Baixo | `_headers`; app testado sob a CSP sem nenhuma violação |

Também verificados: nenhuma chave secreta no repositório nem no build; HTML e script em nomes, avisos e avaliações aparecem como
texto e não executam; rotas como `#/unidade/1' OR 1=1--` e `#/javascript:alert(1)` não derrubam o app; CSP bloqueia script
inline injetado.

## Riscos que permanecem

| Risco | Mitigação |
|---|---|
| Várias contas de uma mesma pessoa podem forçar consenso de localização ou ocultar um aviso | Pesos por reputação, limites configuráveis em `configuracao`, moderação, e-mail confirmado (ligar depois da entrega) |
| A coordenada do registro vem do aparelho e pode ser forjada | `validar_localizacao` (desligada na demonstração); verificação mais forte exigiria validação no servidor |
| Visões públicas pesadas podem ser consultadas em excesso | Limites do provedor, cache, view materializada |
| Servidor público de mapa do OpenStreetMap | Contratar provedor e trocar `TILE_URL` (e a CSP) |
| Triagem sem revisão de profissional de saúde | Revisão clínica antes de uso real |

## Privacidade (LGPD)

| Dado | Finalidade | Retenção |
|---|---|---|
| Nome e e-mail | Conta; nome público abreviado ("Ana S.") | Até excluir a conta |
| Filas, avisos, avaliações, votos, denúncias, sugestões | Calcular espera, informar outros, moderar | Avisos expiram em 4 h; demais até excluir a conta |
| Coordenada do registro de fila | Validar proximidade e dar peso ao registro | Com o registro |
| Plano de ida, preferências, última lista de unidades | Só no aparelho; nada é enviado | Até limpar os dados do navegador |

A localização é lida no aparelho, com permissão, e só é enviada junto com o registro de fila que a pessoa decide fazer. O ponto
escolhido no mapa para buscar a partir de outro lugar não é enviado. O app não coleta sintoma nem diagnóstico (a triagem roda no
aparelho). Direitos atendidos: informação (política de privacidade), acesso (aba Perfil) e eliminação (Perfil > Excluir minha
conta, em cascata). Correção de nome é pedida ao responsável; portabilidade ainda não existe.

Antes de uso real: revisão jurídica dos termos e da política, definição de controlador e encarregado com canal de contato,
contrato e região de armazenamento do Supabase, plano de resposta a incidente, regra para menores de idade, relatório de
impacto se o convênio exigir, e reduzir a precisão da coordenada gravada.

## Como repetir

```bash
cd database && ./tests/rodar_supabase_local.sh pr_supa <scripts 01 a 14, ver README.txt>
psql -U postgres -v ON_ERROR_STOP=1 -d pr_supa -f tests/test_melhorias_14.sql
cd ../app && flutter test && flutter build web --release --no-web-resources-cdn && ./test_e2e/rodar.sh
```
