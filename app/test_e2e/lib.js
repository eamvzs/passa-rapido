const { chromium } = require('playwright');
exports.abrir = async (opts = {}) => {
  const browser = opts.browser || await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } });
  const ctx = await browser.newContext({
    viewport: opts.viewport || { width: 412, height: 870 }, deviceScaleFactor: opts.dsf || 1, ignoreHTTPSErrors: true,
    locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', colorScheme: opts.escuro ? 'dark' : 'light',
    ...(opts.geo ? { geolocation: opts.geo, permissions: ['geolocation'] } : {}),
  });
  const page = await ctx.newPage();
  page.erros = [];
  page.on('console', m => { if (m.type() === 'error' && !/TUNNEL|ERR_FAILED|favicon/.test(m.text())) page.erros.push(m.text().slice(0, 300)); });
  page.on('pageerror', e => page.erros.push('PAGEERROR ' + String(e).slice(0, 300)));
  if (opts.pularApresentacao !== false) await ctx.addInitScript(() => { try { localStorage.setItem('flutter.apresentacao_vista', 'true'); } catch (e) {} });
  await page.goto('http://localhost:' + (process.env.PORTA || 8090) + '/', { waitUntil: 'load' });
  await page.waitForTimeout(opts.espera || 9000);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
  return { browser, ctx, page };
};
exports.passo = async (nome, fn) => { try { await fn(); console.log('ok   ' + nome); return true; } catch (e) { console.log('FALHA ' + nome + ': ' + String(e).split('\n').filter(l => l.trim()).slice(0, 4).join(' / ').slice(0, 420)); return false; } };
exports.foto = async (page, caminho) => { await page.waitForTimeout(1500); await page.screenshot({ path: caminho }); };
// Procura um texto na árvore de acessibilidade (rótulos e conteúdo).
exports.tem = async (page, re) => page.evaluate((src) => {
  const r = new RegExp(src, 'i');
  for (const el of document.querySelectorAll('flt-semantics, flt-semantics *, [aria-label]')) {
    const t = (el.getAttribute('aria-label') || '') + ' ' + (el.children.length === 0 ? (el.textContent || '') : '');
    if (r.test(t)) return true;
  }
  return false;
}, re.source);
exports.textos = async (page) => page.evaluate(() => {
  const out = new Set();
  for (const el of document.querySelectorAll('flt-semantics, flt-semantics *, [aria-label]')) {
    const t = ((el.getAttribute('aria-label') || '') + ' ' + (el.children.length === 0 ? (el.textContent || '') : '')).trim();
    if (t) out.add(t.replace(/\s+/g, ' ').slice(0, 600));
  }
  return [...out];
});
exports.confere = async (nome, cond) => { const ok = await cond; console.log((ok ? 'ok   ' : 'FALHA ') + nome); return ok; };
exports.digitar = async (page, rotulo, texto) => { await page.getByRole('textbox', { name: rotulo }).first().click({ timeout: 6000 }); await page.waitForTimeout(500); await page.keyboard.type(texto, { delay: 25 }); };
// Clica num marcador que esteja na área visível do mapa (fora da busca e da folha de unidades).
exports.clicarMarcador = async (page, re, area = { topo: 150, base: 520 }) => {
  const alvo = await page.evaluate(({ src, area }) => {
    const r = new RegExp(src);
    for (const el of document.querySelectorAll('[role=button]')) {
      const b = el.getBoundingClientRect();
      const cy = b.top + b.height / 2, cx = b.left + b.width / 2;
      if (r.test((el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '')) && cy > area.topo && cy < area.base && cx > 10 && cx < window.innerWidth - 60 && b.width < 120) return { x: cx, y: cy, rotulo: (el.getAttribute('aria-label') || el.textContent || '').slice(0, 80) };
    }
    return null;
  }, { src: re.source, area });
  if (!alvo) throw new Error('nenhum marcador visível para ' + re);
  await page.mouse.click(alvo.x, alvo.y);
  return alvo.rotulo;
};
// Clica num elemento que pode estar fora da tela (as listas do Flutter só montam o que está perto da janela):
// rola de 300 em 300 até o elemento aparecer na área visível e então clica.
exports.clicarRolando = async (page, criar, { x = 206, y = 500, max = 24 } = {}) => {
  await page.mouse.move(x, y);
  for (let i = 0; i < max; i++) {
    const alvo = criar();
    if ((await alvo.count()) > 0) {
      const caixa = await alvo.first().boundingBox().catch(() => null);
      if (caixa && caixa.y > 70 && caixa.y + caixa.height < 790) { await alvo.first().click({ timeout: 4000 }); return; }
      if (caixa && caixa.y <= 70) { await page.mouse.wheel(0, -300); await page.waitForTimeout(250); continue; }
    }
    await page.mouse.wheel(0, 300); await page.waitForTimeout(250);
  }
  throw new Error('elemento não encontrado ao rolar');
};
// A ficha da unidade tem quatro abas (Agora, Ir, Sobre, Opiniões) e cada uma é uma lista preguiçosa:
// percorre as abas rolando e junta os textos de todas.
exports.irParaAba = async (page, nome) => {
  await page.getByRole('button', { name: new RegExp('^' + nome + '(,|$)') }).first().click({ timeout: 5000 });
  await page.waitForTimeout(700);
};
exports.coletarAbas = async (page, { passos = 7 } = {}) => {
  const juntos = [];
  for (const aba of ['Agora', 'Ir', 'Sobre', 'Opiniões']) {
    await exports.irParaAba(page, aba);
    await page.mouse.move(206, 500);
    for (let i = 0; i < passos; i++) {
      for (const x of await exports.textos(page)) if (!juntos.includes(x)) juntos.push(x);
      await page.mouse.wheel(0, 450); await page.waitForTimeout(300);
    }
    for (let i = 0; i < passos + 2; i++) { await page.mouse.wheel(0, -450); await page.waitForTimeout(100); }
  }
  return juntos;
};
