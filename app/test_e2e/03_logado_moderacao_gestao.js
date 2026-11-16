const { abrir, textos, foto, digitar, passo, tem, clicarRolando, irParaAba } = require('./lib.js');
const mock = require('./mock.js');
const L = console.log;
const erros = (page) => page.erros.length ? page.erros.slice(0, 3).join(' ; ') : 'nenhum';
const agoraIso = new Date().toISOString();
const UPA = { latitude: -23.54578, longitude: -46.46133 };
const base = () => ({
  acess: [{ unidade_id: 1, recurso: 'rampa', sim: 3, nao: 0 }],
  relatos: [{ id: 501, unidade_id: 1, usuario_id: '22222222-2222-4222-8222-222222222222', autor: 'Maria S.', tipo: 'sem_medico', descricao: 'Sem médico clínico agora', confirmacoes: 1, criado_em: agoraIso, expira_em: new Date(Date.now() + 3600e3).toISOString() }],
  avaliacoes: [{ id: 701, unidade_id: 1, usuario_id: '33333333-3333-4333-8333-333333333333', autor: 'João P.', nota: 2, comentario: 'Demorou muito', oculta: false, criado_em: agoraIso }],
  impacto: { registros_7d: 3, unidades_7d: 2, pontos_7d: 14, avisos_7d: 1, avaliacoes_7d: 0, sugestoes_aceitas: 1 },
  moderador: true,
  sugestoes: [{ id: 9, unidade_id: 1, unidade_nome: 'UBS Itaquera', unidade_endereco: 'Rua A, 10', campo: 'telefone', descricao: '(11) 5555-1234', autor: 'Ana M.', apoios: 1, criado_em: agoraIso, latitude: null, longitude: null, unidade_latitude: -23.5, unidade_longitude: -46.4 }],
  denuncias: [{ alvo: 'relato', alvo_id: 55, unidade_nome: 'UPA 26 de Agosto', texto: 'Texto ofensivo de teste', denuncias: 3, motivos: 'ofensivo, spam', oculto: true }],
  regioes: [
    { cidade: 'São Paulo', bairro: 'Itaquera', tipo: 'UBS', unidades: 12, abertas_agora: 3, espera_media_min: 41, unidades_com_fila_real: 0, registros_7d: 0, hora_pico: 10, espera_pico_min: 75 },
    { cidade: 'São Paulo', bairro: '=1+1', tipo: 'INSS', unidades: 1, abertas_agora: 0, espera_media_min: null, unidades_com_fila_real: 0, registros_7d: 0, hora_pico: null, espera_pico_min: null },
  ],
});
const logado = async (opcoes) => {
  const r = await abrir(opcoes);
  return r;
};
async function comSessao(opts, estado) {
  const s = mock.sessaoFalsa();
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } });
  const ctx = await browser.newContext({ viewport: opts.viewport || { width: 412, height: 870 }, ignoreHTTPSErrors: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', geolocation: opts.geo, permissions: ['geolocation', 'clipboard-read', 'clipboard-write'] });
  await ctx.addInitScript(([k, v]) => { try { localStorage.setItem('flutter.apresentacao_vista', 'true'); localStorage.setItem(k, v); } catch (e) {} }, [s.chave, s.valor]);
  await mock.instalar(ctx, estado);
  const page = await ctx.newPage();
  page.erros = [];
  page.on('console', m => { if (m.type() === 'error' && !/TUNNEL|ERR_FAILED|favicon|WebSocket|realtime/i.test(m.text())) page.erros.push(m.text().slice(0, 300)); });
  page.on('pageerror', e => page.erros.push('PAGEERROR ' + String(e).slice(0, 300)));
  await page.goto('http://localhost:8090/', { waitUntil: 'load' });
  await page.waitForTimeout(opts.espera || 11000);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
  return { browser, ctx, page };
}
async function irAba(page, nome) {
  await page.getByRole('tab', { name: new RegExp(nome) }).first().click({ timeout: 5000 }).catch(async () => { await page.getByRole('button', { name: new RegExp('^' + nome) }).first().click(); });
  await page.waitForTimeout(1500);
}
(async () => {
  // ---------- Perfil logado + moderação ----------
  {
    const estado = base();
    const { browser, ctx, page } = await comSessao({ geo: UPA }, estado);
    await irAba(page, 'Perfil');
    const t = await textos(page);
    L((t.some(x => /Pessoa de Teste/.test(x)) ? 'ok   ' : 'FALHA ') + 'sessão simulada reconhecida (nome no perfil)');
    L((t.some(x => /Nos últimos 7 dias você enviou 3 registros de fila em 2 unidades, 1 aviso, 1 correção aceita/.test(x)) ? 'ok   ' : 'FALHA ') + 'Sua semana');
    L((t.some(x => /Sugestões e denúncias pendentes/.test(x)) ? 'ok   ' : 'FALHA ') + 'entrada da moderação para moderador');
    await foto(page, 'saida/n_perfil_logado.png');
    await passo('Moderação lista e aceita', async () => {
      await page.getByText(/Sugestões e denúncias pendentes/).first().click({ timeout: 5000 }); await page.waitForTimeout(1500);
      const m = await textos(page);
      for (const re of [/Telefone · UBS Itaquera/, /\(11\) 5555-1234/, /1 outra sugestão igual/, /Texto ofensivo de teste/, /3 denúncias/]) if (!m.some(x => re.test(x))) throw new Error('faltou ' + re);
      await foto(page, 'saida/n_moderacao.png');
      await page.getByRole('button', { name: /^Aceitar$/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1200);
      const c = estado.chamadas.find(x => /fn_analisar_sugestao/.test(x.caminho));
      if (!c || !/"p_aceitar":true/.test(c.corpo) || !/"p_id":9/.test(c.corpo)) throw new Error('chamada não enviada: ' + JSON.stringify(c));
      await page.getByRole('button', { name: /^Restaurar$/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1000);
      const d = estado.chamadas.find(x => /fn_resolver_denuncia/.test(x.caminho));
      if (!d || !/"p_restaurar":true/.test(d.corpo) || !/"p_alvo":"relato"/.test(d.corpo)) throw new Error('resolução não enviada: ' + JSON.stringify(d));
    });
    L('Perfil/Moderação erros:', erros(page));
    await browser.close();
  }
  // ---------- Ficha logada: voto, denúncia, plano ----------
  {
    const estado = base();
    const { browser, ctx, page } = await comSessao({ geo: UPA }, estado);
    await digitar(page, /Buscar/, 'upa 26 de agosto'); await page.waitForTimeout(1500);
    await page.getByRole('button', { name: /UPA 26 de Agosto/ }).first().click({ timeout: 7000 }); await page.waitForTimeout(2000);
    try { await page.getByRole('button', { name: /Ver detalhes/ }).first().click({ timeout: 2500 }); } catch (e) {}
    await page.waitForTimeout(4500);
    await passo('Denunciar aviso envia a denúncia', async () => {
      await page.getByRole('button', { name: /Denunciar este aviso/ }).first().click({ timeout: 5000 }); await page.waitForTimeout(800);
      await page.getByText(/Informação falsa ou enganosa/).first().click({ timeout: 4000 }); await page.waitForTimeout(1200);
      const c = estado.chamadas.find(x => x.caminho === 'denuncia');
      if (!c) throw new Error('nenhum POST em denuncia');
      const corpo = JSON.parse(c.corpo);
      if (corpo.alvo !== 'relato' || corpo.alvo_id !== 501 || corpo.motivo !== 'falso') throw new Error('corpo inesperado ' + c.corpo);
    });
    await passo('Votar "Tem" na rampa envia o voto', async () => {
      await irParaAba(page, 'Sobre');
      await page.mouse.move(206, 500);
      for (let i = 0; i < 14; i++) { if ((await page.getByRole('checkbox', { name: /Tem Rampa de acesso/ }).count()) > 0) break; await page.mouse.wheel(0, 450); await page.waitForTimeout(350); }
      await page.getByRole('checkbox', { name: /Tem Rampa de acesso/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1200);
      const c = estado.chamadas.find(x => x.caminho === 'acessibilidade_voto');
      if (!c) throw new Error('nenhum POST em acessibilidade_voto');
      const corpo = JSON.parse(c.corpo);
      const v = Array.isArray(corpo) ? corpo[0] : corpo;
      if (v.recurso !== 'rampa' || v.existe !== true || v.usuario_id !== mock.UID) throw new Error('corpo inesperado ' + c.corpo);
    });
    await passo('Planejar a ida calcula a saída', async () => {
      await irParaAba(page, 'Ir');
      for (let i = 0; i < 20; i++) { if ((await page.getByRole('button', { name: /Planejar minha ida/ }).count()) > 0) break; await page.mouse.wheel(0, -450); await page.waitForTimeout(250); }
      await page.getByRole('button', { name: /Planejar minha ida/ }).first().click({ timeout: 5000 }); await page.waitForTimeout(1200);
      await foto(page, 'saida/n_plano_data.png');
      await page.getByRole('button', { name: /^20/ }).first().click({ timeout: 4000 }).catch(async () => { await page.getByText(/^20$/).first().click(); });
      await page.getByRole('button', { name: /^OK$/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1000);
      await foto(page, 'saida/n_plano_hora.png');
      await page.getByRole('button', { name: /^OK$/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1500);
      const t = await textos(page);
      const ok = t.find(x => /Plano salvo\. Saia às/.test(x)) || t.find(x => /Saia de casa até/.test(x));
      if (!ok) throw new Error('plano não confirmado');
      L('   ', ok.slice(0, 120));
    });
    await foto(page, 'saida/n_plano_salvo.png');
    L('Ficha logada erros:', erros(page));
    await browser.close();
  }
  // ---------- Gestão ----------
  {
    const estado = base();
    const { browser, ctx, page } = await comSessao({ geo: UPA }, estado);
    await irAba(page, 'Painel');
    await passo('Gestão abre, lista e copia CSV seguro', async () => {
      await clicarRolando(page, () => page.getByText(/Visão por bairro e tipo de unidade/)); await page.waitForTimeout(1500);
      const t = await textos(page);
      await foto(page, 'saida/n_gestao.png'); L('   textos:', t.filter(x => /regiões|Itaquera|Atenção|Visão/.test(x)).map(x => x.slice(0, 90)).join(' || '));
      for (const re of [/Itaquera, UBS\. 12 unidades/, /2 regiões/, /Atenção: nenhuma destas unidades tem fila informada agora/]) if (!t.some(x => re.test(x))) throw new Error('faltou ' + re);
      await foto(page, 'saida/n_gestao.png');
      await page.getByRole('button', { name: /Copiar tabela/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(700);
      const clip = await page.evaluate(() => navigator.clipboard.readText());
      L('   CSV copiado:', clip.split('\n').slice(0, 3).join(' | ').slice(0, 220));
      if (!clip.includes('"\'=1+1"')) throw new Error('campo com fórmula não foi protegido');
    });
    L('Gestão erros:', erros(page));
    await browser.close();
  }
})();
