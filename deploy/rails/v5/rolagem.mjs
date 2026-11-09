// Confere se a casca rola na horizontal com cada tela aberta numa aba (decisão 0028): a casca ocupa a janela, e as grades rolam dentro delas. Em 1.440 e
// 1.024 px (a largura mínima da casca), nenhuma tela pode fazer a página rolar de lado; em tela estreita (LARGURA=390), a casca mostra o aviso de tela pequena.
//   BASE_URL=... V5_EMAIL=... V5_SENHA=... [LARGURA=1024] node rolagem.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? process.argv[2];
const largura = Number(process.env.LARGURA ?? 1440);
const navegador = await chromium.launch();
// Abaixo de 1.024 px, um celular: o aviso de tela pequena vale para tela de toque (padrões de interface, revisão 38); a janela estreita de computador entra com rolagem.
const celular = largura < 1024 ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {};
const pagina = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: largura, height: 900 }, ...celular })).newPage();
await pagina.goto(BASE + '/');
if (largura < 1024) {
    const aviso = await pagina.locator('#aviso-tela:visible').count();
    console.log(aviso ? `ok    aviso de tela pequena em ${largura} px` : `FALHA sem o aviso de tela pequena em ${largura} px`);
    await navegador.close();
    process.exit(aviso ? 0 : 1);
}
await pagina.locator('#entrada:not([hidden])').waitFor();
await pagina.fill('#entrada-email', process.env.V5_EMAIL);
await pagina.fill('#entrada-senha', process.env.V5_SENHA);
await pagina.click('#entrada-botao');
await pagina.locator('#abas .tabs-title').first().waitFor();
const ocioso = async () => { await pagina.waitForTimeout(400); await pagina.waitForFunction(() => window.jQuery && jQuery.active === 0, null, { timeout: 60000 }); await pagina.waitForTimeout(300); };
const raiz = () => pagina.locator('.aba-raiz:visible').first();

const rotas = ['/resumo', '/clientes', '/acionamentos', '/importacoes', '/importacoes/nova', '/importacoes/nova?tipo=pagamentos', '/divergencias-de-valor', '/acordos', '/acordos/pendentes',
    '/promessas/pendentes', '/estornos-a-espera', '/arquivo-de-acordos', '/distribuicao', '/filas', '/operacoes', '/guarda-de-dados', '/configuracao/carteira',
    '/configuracao/metodos-de-recebimento', '/configuracao/politicas-de-pagamento', '/configuracao/segmentos', '/configuracao/enquadramento-financeiro',
    '/configuracao/promessas-e-acordos', '/configuracao/indices', '/configuracao/resultados-de-acionamento', '/configuracao/dados-do-credor', '/importacoes/nova?tipo=estornos'];
// Uma ficha, com as abas internas, e um acordo, achados pelas listas.
await pagina.evaluate(async () => (await import('spa/abas')).abrir('/clientes')); await ocioso();
const ficha = await raiz().locator('.datagrid-row a[href^="/clientes/"]').first().getAttribute('href');
if (ficha) for (const aba of ['', '?aba=acionamentos', '?aba=promessas', '?aba=pagamentos', '?aba=contatos', '?aba=historico']) rotas.push(ficha + aba);
await pagina.evaluate(async () => (await import('spa/abas')).abrir('/acordos')); await ocioso();
const acordo = await raiz().locator('.datagrid-row a[href^="/acordos/"]').first().getAttribute('href').catch(() => null);
if (acordo) rotas.push(acordo);

let rola = 0;
for (const rota of rotas) {
    await pagina.evaluate(async (url) => (await import('spa/abas')).abrir(url), rota);
    await ocioso();
    const r = await pagina.evaluate(() => ({ pagina: document.documentElement.scrollWidth > document.documentElement.clientWidth, h1: [...document.querySelectorAll('.aba-raiz')].find((e) => e.offsetParent)?.querySelector('h1')?.textContent?.trim() }));
    console.log(`${r.pagina ? 'ROLA ' : 'ok   '} ${rota} (${r.h1 ?? 'sem título'})`);
    if (r.pagina || !r.h1) rola++;
    await pagina.evaluate(() => document.querySelector('#abas .tabs-selected .tabs-close')?.click());
}
await navegador.close();
process.exit(rola ? 1 : 0);
