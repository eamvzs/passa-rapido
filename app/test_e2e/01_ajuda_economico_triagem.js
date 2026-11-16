const { abrir, textos, foto, digitar, passo, tem, clicarRolando } = require('./lib.js');
const mock = require('./mock.js');
const geo = { latitude: -23.5394, longitude: -46.4551 };
const L = console.log;
const erros = (page) => page.erros.length ? page.erros.slice(0, 3).join(' ; ') : 'nenhum';
(async () => {
  // ---------- S1: ajuda, modo econômico, triagem (visitante) ----------
  {
    const { browser, ctx, page } = await abrir({ geo, espera: 11000 });
    await mock.instalar(ctx, { acess: [] });
    let tiles = 0; page.on('request', r => { if (/tile\.openstreetmap\.org/.test(r.url())) tiles++; });
    await passo('Perfil abre', async () => { await page.getByRole('tab', { name: /Perfil/ }).first().click({ timeout: 6000 }).catch(async () => { await page.getByRole('button', { name: /Perfil/ }).first().click(); }); await page.waitForTimeout(1500); });
    await passo('Perfil tem Ajuda e Modo econômico', async () => {
      const t = []; await page.mouse.move(206, 500);
      for (let i = 0; i < 9; i++) { for (const x of await textos(page)) if (!t.includes(x)) t.push(x); await page.mouse.wheel(0, 450); await page.waitForTimeout(300); }
      for (let i = 0; i < 12; i++) { await page.mouse.wheel(0, -450); await page.waitForTimeout(100); }
      for (const re of [/Ajuda e direitos/, /Modo econômico/]) if (!t.some(x => re.test(x))) throw new Error('faltando ' + re);
    });
    await foto(page, 'saida/n_perfil.png');
    await passo('Ajuda abre com direitos e siglas', async () => {
      await clicarRolando(page, () => page.getByText(/Como usar, siglas e atendimento prioritário/)); await page.waitForTimeout(1500);
      const t = await textos(page);
      for (const re of [/Como usar em 3 passos/, /Unidade Básica de Saúde/]) if (!t.some(x => re.test(x))) throw new Error('sem ' + re);
      await foto(page, 'saida/n_ajuda.png');
      await page.goBack().catch(() => {}); await page.getByRole('button', { name: /Voltar|Back/ }).first().click({ timeout: 2000 }).catch(() => {});
    });
    await page.waitForTimeout(800);
    const antes = tiles;
    await passo('Liga o modo econômico', async () => {
      await page.getByRole('switch', { name: /Modo econômico/ }).first().click({ timeout: 5000 }).catch(async () => { await page.getByText(/Modo econômico/).first().click(); });
      await page.waitForTimeout(800);
      await page.getByRole('tab', { name: /Mapa/ }).first().click({ timeout: 4000 }).catch(async () => { await page.getByRole('button', { name: /^Mapa/ }).first().click(); });
      await page.waitForTimeout(2500);
      const t = await textos(page);
      if (!t.some(x => /Modo econômico: sem mapa/.test(x))) throw new Error('aviso do modo econômico ausente');
      if (!t.some(x => /UPA|UBS|Poupatempo/.test(x))) throw new Error('lista vazia');
    });
    await foto(page, 'saida/n_leve.png');
    L('   requisições de mapa depois de ligar o modo econômico:', tiles - antes, '(deve ser 0)');
    await passo('Mostrar mapa volta', async () => { await page.getByRole('button', { name: /Mostrar mapa/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(2500); const t = await textos(page); if (t.some(x => /Modo econômico: sem mapa/.test(x))) throw new Error('aviso ainda aparece'); });
    L('S1 erros:', erros(page));
    await browser.close();
  }
  // ---------- S2: triagem ----------
  {
    const { browser, ctx, page } = await abrir({ geo, espera: 11000 });
    await mock.instalar(ctx);
    await passo('Rápido -> triagem', async () => {
      await page.getByRole('tab', { name: /Rápido/ }).first().click({ timeout: 5000 }).catch(async () => { await page.getByRole('button', { name: /Rápido/ }).first().click(); });
      await page.waitForTimeout(1500);
      await page.getByText(/Não sabe qual unidade procurar/).first().click({ timeout: 5000 }); await page.waitForTimeout(1200);
      const t = await textos(page);
      if (!t.some(x => /Uma UBS costuma resolver/.test(x))) throw new Error('resultado inicial deveria ser UBS');
    });
    await passo('Sinal de urgência -> UPA', async () => { await page.getByRole('checkbox', { name: /Febre alta/ }).first().click({ timeout: 4000 }).catch(async () => { await page.getByText(/Febre alta/).first().click(); }); await page.waitForTimeout(600); if (!(await tem(page, /Procure uma UPA ou um pronto-socorro hoje/))) throw new Error('não mudou para UPA'); });
    await passo('Sinal de emergência -> 192', async () => { await page.getByRole('checkbox', { name: /Dor forte ou aperto no peito/ }).first().click({ timeout: 4000 }).catch(async () => { await page.getByText(/Dor forte ou aperto no peito/).first().click(); }); await page.waitForTimeout(600); if (!(await tem(page, /Ligue 192 \(SAMU\) agora/))) throw new Error('não mudou para 192'); if (!(await tem(page, /Ligar 192 agora/))) throw new Error('botão 192 ausente'); });
    await foto(page, 'saida/n_triagem192.png');
    await passo('Desmarca emergência e vai para o mapa filtrado', async () => {
      await page.getByRole('checkbox', { name: /Dor forte ou aperto no peito/ }).first().click({ timeout: 4000 }).catch(async () => { await page.getByText(/Dor forte ou aperto no peito/).first().click(); }); await page.waitForTimeout(500);
      await page.getByRole('button', { name: /Ver UPA e Pronto-socorro no mapa/ }).first().click({ timeout: 4000 }); await page.waitForTimeout(2500);
      const t = await textos(page);
      if (t.some(x => /Qual unidade procurar/.test(x))) throw new Error('não saiu da triagem');
      if (!t.some(x => /UPA/.test(x))) throw new Error('mapa sem UPA');
    });
    await foto(page, 'saida/n_triagem_mapa.png');
    L('S2 erros:', erros(page));
    await browser.close();
  }
})();
