const { abrir, textos, foto, digitar, passo, tem, coletarAbas, irParaAba } = require('./lib.js');
const mock = require('./mock.js');
const geo = { latitude: -23.5394, longitude: -46.4551 };
const L = console.log;
const erros = (page) => page.erros.length ? page.erros.slice(0, 3).join(' ; ') : 'nenhum';
const agoraIso = new Date().toISOString();
async function abrirFicha(page, busca, rotulo) {
  await digitar(page, /Buscar/, busca); await page.waitForTimeout(1500);
  await page.getByRole('button', { name: new RegExp(rotulo) }).first().click({ timeout: 7000 }); await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /Ver detalhes/ }).first().click({ timeout: 2500 }); } catch (e) {}
  await page.waitForTimeout(4500);
}
(async () => {
  const estado = {
    acess: [{ unidade_id: 1, recurso: 'rampa', sim: 3, nao: 0 }, { unidade_id: 1, recurso: 'elevador', sim: 1, nao: 2 }],
    meusVotos: [],
    relatos: [{ id: 501, unidade_id: 1, usuario_id: '22222222-2222-4222-8222-222222222222', autor: 'Maria S.', tipo: 'sem_medico', descricao: 'Sem médico clínico agora', confirmacoes: 1, criado_em: agoraIso, expira_em: new Date(Date.now() + 3600e3).toISOString() }],
    avaliacoes: [
      { id: 701, unidade_id: 1, usuario_id: '33333333-3333-4333-8333-333333333333', autor: 'João P.', nota: 2, comentario: 'Demorou muito', oculta: false, criado_em: agoraIso },
      { id: 702, unidade_id: 1, usuario_id: '44444444-4444-4444-8444-444444444444', autor: 'Fulano X.', nota: 1, comentario: null, oculta: true, criado_em: agoraIso },
    ],
    impacto: { registros_7d: 3, unidades_7d: 2, pontos_7d: 14, avisos_7d: 1, avaliacoes_7d: 0, sugestoes_aceitas: 1 },
    moderador: true,
    sugestoes: [{ id: 9, unidade_id: 1, unidade_nome: 'UBS Itaquera', unidade_endereco: 'Rua A, 10', campo: 'telefone', descricao: '(11) 5555-1234', autor: 'Ana M.', apoios: 1, criado_em: agoraIso, latitude: null, longitude: null, unidade_latitude: -23.5, unidade_longitude: -46.4 }],
    denuncias: [{ alvo: 'relato', alvo_id: 55, unidade_nome: 'UPA 26 de Agosto', texto: 'Texto ofensivo de teste', denuncias: 3, motivos: 'ofensivo, spam', oculto: true }],
    regioes: [
      { cidade: 'São Paulo', bairro: 'Itaquera', tipo: 'UBS', unidades: 12, abertas_agora: 3, espera_media_min: 41, unidades_com_fila_real: 0, registros_7d: 0, hora_pico: 10, espera_pico_min: 75 },
      { cidade: 'São Paulo', bairro: 'Lapa', tipo: 'UPA', unidades: 1, abertas_agora: 1, espera_media_min: 20, unidades_com_fila_real: 1, registros_7d: 5, hora_pico: 19, espera_pico_min: 50 },
      { cidade: 'São Paulo', bairro: '=1+1', tipo: 'INSS', unidades: 1, abertas_agora: 0, espera_media_min: null, unidades_com_fila_real: 0, registros_7d: 0, hora_pico: null, espera_pico_min: null },
    ],
  };
  // ---------- S3: ficha como visitante ----------
  {
    const { browser, ctx, page } = await abrir({ geo, espera: 11000 });
    await mock.instalar(ctx, estado);
    const urlsAbertas = [];
    await ctx.route(/google\.com\/maps/, (route) => { urlsAbertas.push(route.request().url()); route.fulfill({ status: 200, contentType: 'text/html', body: 'ok' }); });
    await abrirFicha(page, 'upa 26 de agosto', 'UPA 26 de Agosto');
    await foto(page, 'saida/n_ficha_topo.png');
    const t = await coletarAbas(page);
    for (const [nome, re] of [['feriado', /Hoje é feriado \(Proclamação da República\)/], ['planeje', /Planeje sua ida/], ['o que levar', /O que levar/], ['acessib.', /Acessibilidade e prioridade/], ['prioridade', /Leis 10\.048/], ['rampa confirmada', /Rampa de acesso: Confirmado por 3 pessoas/], ['elevador negado', /Elevador: 2 pessoas dizem que não tem/], ['aviso', /Sem médico/], ['denunciar aviso', /Denunciar este aviso/], ['comentário oculto', /Comentário removido após denúncias/]]) {
      L((t.some(x => re.test(x)) ? 'ok   ' : 'FALHA ') + 'ficha: ' + nome);
    }
    await foto(page, 'saida/n_ficha0.png');
    await irParaAba(page, 'Agora');
    await passo('Como chegar abre escolha de modo', async () => {
      await page.getByRole('button', { name: /Como chegar/ }).first().click({ timeout: 5000 }); await page.waitForTimeout(900);
      const t2 = await textos(page);
      for (const re of [/Transporte público/, /A pé/, /Carro, moto ou aplicativo/, /Bicicleta/]) if (!t2.some(x => re.test(x))) throw new Error('sem ' + re);
      await page.getByRole('button', { name: /^A pé/ }).first().click({ timeout: 4000 }).catch(() => page.getByText(/^A pé$/).first().click());
      await page.waitForTimeout(1500);
      const alvo = urlsAbertas[urlsAbertas.length - 1] || '(nenhuma URL aberta)';
      L('   URL aberta:', alvo.slice(0, 150));
      if (!/travelmode=walking/.test(alvo)) throw new Error('modo errado');
    });
    await page.waitForTimeout(500);
    await passo('Voto de acessibilidade pede login', async () => {
      await page.getByRole('button', { name: /Tem Rampa de acesso/ }).first().scrollIntoViewIfNeeded().catch(() => {});
    });
    L('S3 erros:', erros(page));
    await browser.close();
  }
  // ---------- S4: logado ----------
  {
    const { browser, ctx, page } = await abrir({ geo, espera: 1000 });
    await browser.close();
  }
})();
