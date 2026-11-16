// Simulação do backend para o QA de telas que exigem conta e do script 14 (ainda não aplicado na nuvem).
const REF = 'ccjkejxcvisauiplflvb';
const UID = '11111111-1111-4111-8111-111111111111';
exports.UID = UID;

exports.sessaoFalsa = () => {
  const agora = Math.floor(Date.now() / 1000);
  const sessao = {
    access_token: 'x.' + Buffer.from(JSON.stringify({ sub: UID, role: 'authenticated', exp: agora + 7200 })).toString('base64url') + '.y',
    refresh_token: 'refresh-falso', token_type: 'bearer', expires_in: 7200, expires_at: agora + 7200,
    user: { id: UID, aud: 'authenticated', role: 'authenticated', email: 'qa@example.com', app_metadata: {}, user_metadata: { nome: 'Pessoa de Teste' }, created_at: new Date().toISOString() },
  };
  return { chave: `sb-${REF}-auth-token`, valor: JSON.stringify(sessao) };
};

// opts.moderador, opts.relatos, opts.avaliacoes, opts.acess, opts.regioes, opts.impacto ...
exports.instalar = async (ctx, estado = {}) => {
  const chamadas = [];
  estado.chamadas = chamadas;
  await ctx.route(new RegExp('https://' + REF + '\\.supabase\\.co/(rest|auth)/v1/.*'), async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const caminho = url.pathname.replace('/rest/v1/', '');
    const metodo = req.method();
    const unico = (req.headers()['accept'] || '').includes('vnd.pgrst.object');
    const json = (corpo, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(corpo), headers: { 'access-control-allow-origin': '*' } });
    if (metodo === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    if (metodo !== 'GET') chamadas.push({ metodo, caminho, corpo: req.postData() });
    if (url.pathname.startsWith('/auth/v1')) return json({ message: 'sem rede de autenticação no QA' }, 400);

    if (estado.derrubarRede && !caminho.startsWith('rpc/fn_meu') ) return route.abort();
    switch (true) {
      case caminho === 'vw_acessibilidade_unidade': return json(estado.acess ?? []);
      case caminho === 'acessibilidade_voto': return metodo === 'GET' ? json(estado.meusVotos ?? []) : json([], 201);
      case caminho === 'vw_gestao_regiao': return json(estado.regioes ?? []);
      case caminho === 'rpc/fn_meu_impacto': return json([estado.impacto ?? { registros_7d: 0, unidades_7d: 0, pontos_7d: 0, avisos_7d: 0, avaliacoes_7d: 0, sugestoes_aceitas: 0 }]);
      case caminho === 'rpc/fn_sou_moderador': return json(!!estado.moderador);
      case caminho === 'rpc/fn_listar_sugestoes_pendentes': return json(estado.sugestoes ?? []);
      case caminho === 'rpc/fn_listar_denuncias_pendentes': return json(estado.denuncias ?? []);
      case caminho.startsWith('rpc/fn_analisar_sugestao') || caminho.startsWith('rpc/fn_resolver_denuncia'): estado.sugestoes = []; estado.denuncias = estado.denuncias; return json(null, 204);
      case caminho === 'denuncia': return json([], 201);
      case caminho === 'vw_relato_publico': return json(estado.relatos ?? []);
      case caminho === 'vw_avaliacao_publica': return json(estado.avaliacoes ?? []);
      case caminho === 'usuario': { const u = { id: UID, nome: 'Pessoa de Teste', pontos: 42, nivel: 'iniciante', confiabilidade: 50 }; return json(unico ? u : [u]); }
      case caminho === 'notificacao' || caminho === 'favorito' || caminho === 'sugestao_correcao': return json(metodo === 'GET' ? [] : [], metodo === 'GET' ? 200 : 201);
      case caminho === 'registro_fila': if (metodo === 'GET') return unico ? json(null) : json([]); return json({ id: 1, unidade_id: 1, tipo: 'observacao', tamanho_fila: 'curta', status: 'aguardando', chegada_em: new Date().toISOString() }, 201);
      default: { const h = { ...req.headers() }; delete h['authorization']; return route.continue({ headers: h }); }
    }
  });
  return estado;
};
