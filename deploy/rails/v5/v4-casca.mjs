// V4 da casca (SPA em EasyUI, plano técnico, Verificação): primeira carga, abrir aba em até 1 s, grade com 200 mil clientes e memória com 12 abas.
// Os tempos são medidos dentro da página (performance.now), do pedido até a tela pronta: a aba com o título e nenhum pedido do jQuery em andamento.
// A memória e os nós vêm do Chromium (CDP), depois de forçar a coleta de lixo.
//
//   bin/rails crm:measure_shell[200000]      (credor de medição; imprime V4_EMAIL e V4_SENHA)
//   V4_EMAIL=... V4_SENHA=... deploy/rails/v5/v5.sh v4-casca.mjs http://127.0.0.1:3231
// (o v5.sh passa V5_EMAIL e V5_SENHA dos usuários públicos; aqui valem V4_EMAIL e V4_SENHA, se vierem.)
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? process.argv[2];
const EMAIL = process.env.V4_EMAIL ?? process.env.V5_EMAIL;
const SENHA = process.env.V4_SENHA ?? process.env.V5_SENHA;
const navegador = await chromium.launch();
const contexto = await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } });
const pagina = await contexto.newPage();
pagina.setDefaultTimeout(60000);
const cdp = await contexto.newCDPSession(pagina);
await cdp.send('Performance.enable');
const linhas = [];
const anotar = (medida, valor, meta) => {
    const texto = `${medida.padEnd(58)} ${valor}${meta ? `   (meta: ${meta})` : ''}`;
    linhas.push(texto);
    console.log(texto);
};

// Espera, dentro da página, a condição e os pedidos do jQuery terminarem; devolve os milissegundos desde `inicio`.
const pronto = (inicio, seletor, texto) => pagina.evaluate(([inicio, seletor, texto]) => new Promise((resolver) => {
    const conferir = () => {
        const alvo = [...document.querySelectorAll(seletor)].find((el) => el.offsetParent && (!texto || el.textContent.includes(texto)));
        if (alvo && window.jQuery && jQuery.active === 0) resolver(performance.now() - inicio);
        else requestAnimationFrame(conferir);
    };
    conferir();
}), [inicio, seletor, texto]);

const abrirAba = async (url, titulo) => {
    const inicio = await pagina.evaluate(async (url) => { const abas = await import('spa/abas'); const t = performance.now(); abas.abrir(url); return t; }, url);
    return pronto(inicio, '.aba-raiz h1', titulo);
};

const memoria = async () => {
    await cdp.send('HeapProfiler.enable');
    await cdp.send('HeapProfiler.collectGarbage');
    await pagina.waitForTimeout(500);
    const { metrics } = await cdp.send('Performance.getMetrics');
    const m = Object.fromEntries(metrics.map(({ name, value }) => [name, value]));
    return { heap: (m.JSHeapUsedSize / 1048576).toFixed(1), nos: m.Nodes };
};

// 1. Primeira carga: da navegação até a entrada à vista, e da entrada até o Resumo pronto.
await pagina.goto(BASE + '/');
await pagina.locator('#entrada:not([hidden])').waitFor();
const navegacao = await pagina.evaluate(() => performance.now());
anotar('primeira carga: da navegação até a entrada à vista', `${Math.round(navegacao)} ms`);
await pagina.fill('#entrada-email', EMAIL);
await pagina.fill('#entrada-senha', SENHA);
const inicioEntrada = await pagina.evaluate(() => { document.querySelector('#entrada-botao').click(); return performance.now(); });
anotar('entrar: do clique até o Resumo pronto', `${Math.round(await pronto(inicioEntrada, '.aba-raiz h1', 'Resumo da carteira'))} ms`);
anotar('memória depois de entrar', JSON.stringify(await memoria()));

// 2. Abrir cada tela numa aba (a primeira vez, sem cache do trecho).
const telas = [
    ['/clientes', 'Clientes'], ['/acionamentos', 'Acionamentos'], ['/acordos', 'Acordos'], ['/promessas/pendentes', 'Promessas pendentes'],
    ['/divergencias-de-valor', 'Divergências de valor'], ['/importacoes', 'Importações'], ['/distribuicao', 'Distribuição'], ['/filas', 'Filas'],
    ['/configuracao/segmentos', 'Segmentos'], ['/configuracao/enquadramento-financeiro', 'Enquadramento financeiro'], ['/usuarios', 'Usuários'],
];
const tempos = [];
for (const [url, titulo] of telas) {
    const ms = await abrirAba(url, titulo);
    tempos.push(ms);
    anotar(`abrir aba ${url}`, `${Math.round(ms)} ms`, '1.000 ms');
}
anotar('memória com 12 abas (Resumo + 11)', JSON.stringify(await memoria()));

// 3. Grade de clientes com o credor de 200 mil: página seguinte, ordenar e buscar, cada um até a grade pronta.
await pagina.locator('.tabs-inner', { hasText: 'Clientes' }).first().click();
await pagina.waitForTimeout(300);
const total = await pagina.locator('.aba-raiz:visible .pagination-info').first().textContent();
anotar('grade de clientes: total', total.trim());
const medirGrade = async (acao) => {
    const inicio = await pagina.evaluate(() => performance.now());
    await acao();
    await pagina.waitForTimeout(50);
    return Math.round(await pronto(inicio, '.aba-raiz .datagrid-row'));
};
anotar('grade: página seguinte', `${await medirGrade(() => pagina.locator('.aba-raiz:visible .pagination-next').first().click())} ms`, '1.000 ms');
anotar('grade: ordenar por Vencido', `${await medirGrade(() => pagina.locator('.aba-raiz:visible .datagrid-header td', { hasText: 'Vencido' }).first().click())} ms`, '1.000 ms');
anotar('grade: buscar um nome', `${await medirGrade(async () => { await pagina.locator('.aba-raiz:visible input[placeholder*="Nome"]').first().fill('Cliente 123456'); await pagina.waitForTimeout(400); })} ms (a busca espera 300 ms depois da última tecla)`, '1.000 ms');
const ficha = await (async () => {
    const inicio = await pagina.evaluate(() => { document.querySelector('.aba-raiz .datagrid-row a')?.click(); return performance.now(); });
    return Math.round(await pronto(inicio, '.aba-raiz .cabecalho-da-pagina h1', 'Cliente 123456'));
})();
anotar('ficha de um cliente a partir da grade', `${ficha} ms`, '1.000 ms');

// 4. Fechar todas as abas de trabalho e medir de novo (sobras no body).
await pagina.evaluate(() => { const abas = jQuery('#abas'); for (let i = abas.tabs('tabs').length - 1; i > 0; i--) abas.tabs('close', i); });
await pagina.waitForTimeout(800);
anotar('memória depois de fechar as abas', JSON.stringify(await memoria()));

const acima = tempos.filter((ms) => ms > 1000).length;
anotar('abas acima de 1 s', `${acima} de ${tempos.length}`);
await navegador.close();
