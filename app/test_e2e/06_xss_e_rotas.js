const { chromium } = require('playwright');
const { textos, digitar, coletarAbas } = require('./lib.js');
const mock = require('./mock.js');
const L = console.log;
(async () => {
  const browser = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } });
  const ctx = await browser.newContext({ viewport: { width: 412, height: 870 }, ignoreHTTPSErrors: true, locale: 'pt-BR', geolocation: { latitude: -23.5394, longitude: -46.4551 }, permissions: ['geolocation'] });
  await ctx.addInitScript(() => { localStorage.setItem('flutter.apresentacao_vista', 'true'); window.__csp = []; document.addEventListener('securitypolicyviolation', e => window.__csp.push(e.violatedDirective)); });
  const payload = `<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>"><svg onload=window.__xss=3>`;
  await mock.instalar(ctx, {
    relatos: [{ id: 1, unidade_id: 1, proprio: false, autor: payload, tipo: 'outro', descricao: payload, confirmacoes: 0, criado_em: new Date().toISOString(), expira_em: new Date(Date.now() + 3600e3).toISOString() }],
    avaliacoes: [{ id: 2, unidade_id: 1, proprio: false, autor: payload, nota: 3, comentario: payload, oculta: false, criado_em: new Date().toISOString() }],
  });
  const page = await ctx.newPage();
  await page.goto('http://localhost:' + (process.env.PORTA_CSP || 8091) + '/', { waitUntil: 'load' }); await page.waitForTimeout(13000);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await page.waitForTimeout(800);

  // controle negativo: a CSP realmente bloqueia script inline?
  const inline = await page.evaluate(() => { const s = document.createElement('script'); s.textContent = 'window.__teste_inline = 1'; document.head.appendChild(s); return window.__teste_inline === 1; });
  const viol = await page.evaluate(() => window.__csp.slice());
  L('script inline injetado executou?', inline, '(deve ser false) | violação registrada:', viol.includes('script-src-elem') || viol.includes('script-src'));

  await digitar(page, /Buscar/, 'upa 26 de agosto'); await page.waitForTimeout(1500);
  await page.getByRole('button', { name: /UPA 26 de Agosto/ }).first().click(); await page.waitForTimeout(1500);
  try { await page.getByRole('button', { name: /Ver detalhes/ }).first().click({ timeout: 2500 }); } catch (e) {}
  await page.waitForTimeout(4500);
  const t = await coletarAbas(page, { passos: 5 });
  const aparece = t.some(x => x.includes('<img src=x'));
  const xss = await page.evaluate(() => window.__xss);
  L('texto malicioso apareceu como texto puro (não executado)?', aparece, '| window.__xss =', xss, '(deve ser undefined)');
  const dom = await page.evaluate(() => document.querySelectorAll('img[src="x"], svg[onload]').length);
  L('elementos injetados no DOM:', dom, '(deve ser 0)');
  await browser.close();

  // rotas malformadas
  const b2 = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } });
  const c2 = await b2.newContext({ viewport: { width: 412, height: 870 }, ignoreHTTPSErrors: true });
  await c2.addInitScript(() => localStorage.setItem('flutter.apresentacao_vista', 'true'));
  for (const rota of ['#/unidade/abc', '#/unidade/99999999999999999999999', "#/unidade/1'%20OR%201=1--", '#/unidade/-5', '#/../../etc/passwd', '#/javascript:alert(1)']) {
    const p = await c2.newPage(); const erros = [];
    p.on('pageerror', e => erros.push(String(e).slice(0, 120)));
    await p.goto('http://localhost:' + (process.env.PORTA_CSP || 8091) + '/' + rota, { waitUntil: 'load' }); await p.waitForTimeout(9000);
    const vivo = await p.evaluate(() => !!document.querySelector('flutter-view, flt-glass-pane'));
    L('rota', rota.padEnd(32), '-> app de pé:', vivo, '| erros de página:', erros.length ? erros[0] : 'nenhum');
    await p.close();
  }
  await b2.close();
})();
