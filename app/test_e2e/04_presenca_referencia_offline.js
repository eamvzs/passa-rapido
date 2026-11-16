const { abrir, textos, foto, digitar, passo, tem, clicarRolando } = require('./lib.js');
const mock = require('./mock.js');
const L = console.log;
const erros = (page) => page.erros.length ? page.erros.slice(0, 3).join(' ; ') : 'nenhum';
const UPA = { latitude: -23.54578, longitude: -46.46133 };
async function comSessao(opts, estado) {
  const s = mock.sessaoFalsa();
  const { chromium } = require('playwright');
  const browser = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY, bypass: 'localhost,127.0.0.1' } });
  const ctx = await browser.newContext({ viewport: opts.viewport || { width: 412, height: 870 }, ignoreHTTPSErrors: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', geolocation: opts.geo, permissions: ['geolocation', 'clipboard-read', 'clipboard-write'] });
  await ctx.addInitScript(([k, v, logado]) => { try { localStorage.setItem('flutter.apresentacao_vista', 'true'); if (logado) localStorage.setItem(k, v); } catch (e) {} }, [s.chave, s.valor, opts.logado !== false]);
  await mock.instalar(ctx, estado);
  if (opts.relogioFalso) await ctx.clock.install();
  const page = await ctx.newPage();
  page.erros = [];
  page.on('console', m => { if (m.type() === 'error' && !/TUNNEL|ERR_FAILED|favicon|WebSocket|realtime|Failed to load resource/i.test(m.text())) page.erros.push(m.text().slice(0, 300)); });
  page.on('pageerror', e => page.erros.push('PAGEERROR ' + String(e).slice(0, 300)));
  await page.goto('http://localhost:8090/', { waitUntil: 'load' });
  await page.waitForTimeout(opts.espera || 11000);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
  return { browser, ctx, page };
}
(async () => {
  // ---------- Presença: "Como está a fila?" ----------
  {
    const estado = {};
    const { browser, ctx, page } = await comSessao({ geo: UPA, relogioFalso: true }, estado);
    await passo('Pergunta de fila aparece depois de 10 min dentro da unidade', async () => {
      await page.clock.fastForward(31000); await page.waitForTimeout(800);      // 1ª checagem: marca a chegada
      await page.clock.fastForward('09:00'); await page.waitForTimeout(800);   // 9 min: ainda não
      if (await tem(page, /Como está a fila agora/)) throw new Error('perguntou antes de 10 min');
      await page.clock.fastForward('02:00'); await page.waitForTimeout(1500);  // 11 min
      if (!(await tem(page, /Como está a fila agora/))) throw new Error('a pergunta não apareceu depois de 11 min simulados');
      await foto(page, 'saida/n_presenca.png');
      await page.getByRole('button', { name: /^Curta/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1500);
      const c = estado.chamadas.find(x => x.caminho === 'registro_fila');
      if (!c) throw new Error('registro não enviado');
      const corpo = JSON.parse(c.corpo); const v = Array.isArray(corpo) ? corpo[0] : corpo;
      L('   registro enviado:', JSON.stringify(v));
      if (v.tipo !== 'observacao' || v.tamanho_fila !== 'curta') throw new Error('corpo inesperado');
    });
    await passo('Não pergunta de novo logo em seguida', async () => {
      await page.clock.fastForward('05:00'); await page.waitForTimeout(1200);
      if (await tem(page, /Como está a fila agora/)) throw new Error('perguntou de novo');
    });
    L('Presença erros:', erros(page));
    await browser.close();
  }
  // ---------- Visitante nunca é perguntado ----------
  {
    const { browser, ctx, page } = await comSessao({ geo: UPA, logado: false, relogioFalso: true }, {});
    await passo('Sem login não há pergunta', async () => {
      await page.clock.fastForward(31000); await page.waitForTimeout(500);
      await page.clock.fastForward('12:00'); await page.waitForTimeout(1200);
      if (await tem(page, /Como está a fila agora/)) throw new Error('perguntou a um visitante');
    });
    await browser.close();
  }
  // ---------- Ponto de referência + Ajuda ----------
  {
    const { browser, ctx, page } = await comSessao({ geo: { latitude: -23.5394, longitude: -46.4551 }, logado: false }, {});
    await passo('Toque longo no mapa escolhe outro ponto de partida', async () => {
      await page.mouse.move(250, 330); await page.mouse.down(); await page.waitForTimeout(1100); await page.mouse.up(); await page.waitForTimeout(900);
      if (!(await tem(page, /Buscando a partir do ponto escolhido/))) throw new Error('aviso não apareceu');
      if ((await page.getByRole('button', { name: /Voltar a buscar a partir da minha localização/ }).count()) === 0) throw new Error('botão de voltar ausente');
      await foto(page, 'saida/n_referencia.png');
    });
    await passo('Aba Rápido mostra que busca de outro ponto e volta ao normal', async () => {
      await page.getByRole('tab', { name: /Rápido/ }).first().click({ timeout: 5000 }).catch(async () => { await page.getByRole('button', { name: /^Rápido/ }).first().click(); });
      await page.waitForTimeout(2500);
      if (!(await tem(page, /Buscando a partir do ponto que você escolheu no mapa/))) throw new Error('faixa ausente');
      await foto(page, 'saida/n_rapido_ref.png');
      await page.getByRole('button', { name: /Voltar à minha localização/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(1000);
      if (await tem(page, /Buscando a partir do ponto que você escolheu/)) throw new Error('faixa continua');
    });
    await passo('Ajuda mostra direitos e siglas', async () => {
      await page.getByRole('tab', { name: /Perfil/ }).first().click({ timeout: 5000 }).catch(async () => { await page.getByRole('button', { name: /^Perfil/ }).first().click(); });
      await page.waitForTimeout(1500);
      await clicarRolando(page, () => page.getByText(/Como usar, siglas e atendimento prioritário/));
      await page.waitForTimeout(1500);
      const t = []; await page.mouse.move(206, 500);
      for (let i = 0; i < 10; i++) { for (const x of await textos(page)) if (!t.includes(x)) t.push(x); if (i === 0) await foto(page, 'saida/n_ajuda.png'); await page.mouse.wheel(0, 450); await page.waitForTimeout(300); }
      for (const re of [/Como usar em 3 passos/, /Unidade Básica de Saúde/, /Atendimento prioritário/, /10\.048/, /Internet fraca/]) if (!t.some(x => re.test(x))) throw new Error('faltou ' + re);
    });
    L('Referência/Ajuda erros:', erros(page));
    await browser.close();
  }
  // ---------- Offline ----------
  {
    const estado = {};
    const { browser, ctx, page } = await comSessao({ geo: { latitude: -23.5394, longitude: -46.4551 }, logado: false }, estado);
    const t0 = await textos(page);
    L('antes (online): unidades visíveis:', t0.some(x => /UPA|UBS/.test(x)));
    await passo('Sem conexão mostra a cópia salva e avisa a hora', async () => {
      estado.derrubarRede = true;
      await page.reload({ waitUntil: 'load' }); await page.waitForTimeout(12000);
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await page.waitForTimeout(800);
      const t = await textos(page);
      const aviso = t.find(x => /Sem conexão\. Mostrando os dados salvos às \d\d:\d\d/.test(x));
      L('   aviso:', aviso ? aviso.slice(0, 110) : '(ausente)');
      if (!aviso) throw new Error('aviso de dados salvos ausente');
      if (!t.some(x => /UPA|UBS|Pronto/.test(x))) throw new Error('lista vazia mesmo com cópia');
      await foto(page, 'saida/n_offline.png');
    });
    L('Offline erros:', erros(page));
    await browser.close();
  }
})();
