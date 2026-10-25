// Confere se a página ou alguma tabela rola na horizontal. Em desktop (1440 px, padrão) nenhuma das duas; em tela estreita (LARGURA=390), só a página não
// pode rolar (a tabela rola dentro do contêiner `.tabela`, como manda o design system).
//   BASE_URL=... V5_EMAIL=... V5_SENHA=... [LARGURA=390] node rolagem.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? process.argv[2];
const largura = Number(process.env.LARGURA ?? 1440);
const navegador = await chromium.launch();
const pagina = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: largura, height: 900 } })).newPage();
await pagina.goto(BASE + '/session/new');
await pagina.fill('#email_address', process.env.V5_EMAIL);
await pagina.fill('#password', process.env.V5_SENHA);
await pagina.click('button[type=submit]');
await pagina.waitForURL(BASE + '/');

const rotas = ['/', '/clientes', '/acionamentos', '/importacoes', '/importacoes/nova', '/importacoes/nova?kind=payments', '/divergencias-de-valor', '/acordos', '/acordos/pendentes',
    '/promessas/pendentes', '/estornos-a-espera', '/arquivo-de-acordos', '/guarda-de-dados', '/configuracao/carteira', '/configuracao/canais-de-recebimento',
    '/configuracao/politicas-de-pagamento', '/configuracao/contas-de-pagamento', '/configuracao/segmentos', '/configuracao/promessas-e-acordos', '/configuracao/indices',
    '/configuracao/resultados-de-acionamento'];
await pagina.goto(BASE + '/clientes');
await pagina.locator('tbody tr').first().getByRole('link').first().click();
await pagina.waitForURL(/\/clientes\/\d+/);
rotas.push(new URL(pagina.url()).pathname);
await pagina.goto(BASE + '/acordos');
const acordo = pagina.locator('tbody tr a[href^="/acordos/"]').first();
if ((await acordo.count()) > 0) rotas.push(new URL(await acordo.evaluate((a) => a.href)).pathname);

let rola = 0;
for (const rota of rotas) {
    const resposta = await pagina.goto(BASE + rota);
    await pagina.waitForLoadState('networkidle');
    const estreita = largura < 1280;
    const r = await pagina.evaluate(() => ({
        pagina: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        tabelas: [...document.querySelectorAll('.tabela')].filter((e) => e.scrollWidth > e.clientWidth + 1).length,
    }));
    const rolou = r.pagina || (!estreita && r.tabelas > 0);
    console.log(`${rolou ? 'ROLA ' : 'ok   '} ${rota} (${resposta.status()}; página: ${r.pagina}, tabelas: ${r.tabelas})`);
    if (rolou) rola++;
}
await navegador.close();
process.exit(rola ? 1 : 0);
