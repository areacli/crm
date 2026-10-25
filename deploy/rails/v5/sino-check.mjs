// Verifica que o sino do cabeçalho se atualiza sozinho (Action Cable, sem polling; decisão 0020): entra com o usuário público, espera a assinatura do
// canal de avisos, imprime PRONTO e espera o contador do sino aparecer. Quem roda cria o aviso em outro terminal (sino-check.sh).
//
//   BASE_URL=... V5_EMAIL=... V5_SENHA=... node sino-check.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? process.argv[2];
const navegador = await chromium.launch();
const pagina = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
await pagina.goto(BASE + '/session/new');
await pagina.fill('#email_address', process.env.V5_EMAIL);
await pagina.fill('#password', process.env.V5_SENHA);
await pagina.click('button[type=submit]');
await pagina.waitForURL(BASE + '/');
// Espera a assinatura do canal de avisos do usuário antes de dizer que está pronto.
await pagina.waitForFunction(() => document.documentElement.dataset.cable === 'conectado' && window.cable?.canais?.some((c) => c.channel === 'NoticesChannel'), null, { timeout: 30000 });
await pagina.waitForLoadState('networkidle');
console.log('PRONTO');
try {
    await pagina.locator('#sino .contador').first().waitFor({ timeout: Number(process.env.SINO_TIMEOUT ?? 60) * 1000 });
    console.log('OK: o sino mostrou o aviso sem recarregar a página');
    await navegador.close();
} catch {
    console.error('FALHA: o sino não mudou');
    await navegador.close();
    process.exit(1);
}
