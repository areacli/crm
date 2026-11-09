// Verifica que o sino da casca se atualiza sozinho (Action Cable, sem polling; decisões 0020 e 0028): entra com o usuário público na casca, espera a conexão do
// WebSocket, imprime PRONTO e espera o contador do sino aparecer. Quem roda cria o aviso em outro terminal (sino-check.sh).
//
//   BASE_URL=... V5_EMAIL=... V5_SENHA=... node sino-check.mjs
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? process.argv[2];
const navegador = await chromium.launch();
const pagina = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
await pagina.goto(BASE + '/');
await pagina.locator('#entrada:not([hidden])').waitFor();
await pagina.fill('#entrada-email', process.env.V5_EMAIL);
await pagina.fill('#entrada-senha', process.env.V5_SENHA);
await pagina.click('#entrada-botao');
await pagina.locator('#abas .tabs-title').first().waitFor();
// A assinatura do canal de avisos sai com o menu; a faixa de conexão caída escondida e a rede parada dizem que ela está de pé.
await pagina.waitForFunction(() => document.querySelector('#sem-conexao')?.hidden !== false && window.jQuery && jQuery.active === 0, null, { timeout: 30000 });
await pagina.waitForLoadState('networkidle');
await pagina.waitForTimeout(1500);
const antes = await pagina.locator('#sino .contador').textContent();
console.log('PRONTO');
try {
    await pagina.waitForFunction((anterior) => { const c = document.querySelector('#sino .contador'); return c && !c.hidden && c.textContent !== anterior }, antes, { timeout: Number(process.env.SINO_TIMEOUT ?? 60) * 1000 });
    console.log('OK: o sino mostrou o aviso sem recarregar a página');
    await navegador.close();
} catch {
    console.error('FALHA: o sino não mudou');
    await navegador.close();
    process.exit(1);
}
