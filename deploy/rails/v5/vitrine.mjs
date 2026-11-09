// Fotos do carrossel da entrada da demonstração (`layouts/_vitrine`): cinco telas com os dados fictícios, sem a faixa de aviso, em WebP de 1.120 × 630.
// Grava em /telas; copie os .webp para src/app/assets/images/vitrine.
//   deploy/rails/v5/v5.sh vitrine.mjs https://crm.areacli.com
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const BASE = process.env.BASE_URL ?? process.argv[2];
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 1440, height: 834 }, ignoreHTTPSErrors: true })).newPage();
p.setDefaultTimeout(60000);
await p.goto(`${BASE}/`);
await p.fill('#entrada-email', process.env.V5_EMAIL);
await p.fill('#entrada-senha', process.env.V5_SENHA);
await p.click('#entrada-botao');
await p.locator('#abas .tabs-title').first().waitFor();
const ocioso = async () => { await p.waitForTimeout(500); await p.waitForFunction(() => window.jQuery && jQuery.active === 0); await p.waitForTimeout(900); };
const abrir = async (url) => { await p.evaluate(async (u) => (await import('spa/abas')).abrir(u), url); await p.locator('.aba-raiz:visible').first().waitFor(); await ocioso(); };
const fechar = () => p.evaluate(() => document.querySelector('#abas .tabs-selected .tabs-close')?.click());
const foto = async (nome) => {
    const png = await p.screenshot({ clip: { x: 0, y: 24, width: 1440, height: 810 } });
    const webp = await p.evaluate(async (b64) => {
        const imagem = new Image();
        imagem.src = `data:image/png;base64,${b64}`;
        await imagem.decode();
        const tela = Object.assign(document.createElement('canvas'), { width: 1120, height: 630 });
        const contexto = tela.getContext('2d');
        contexto.imageSmoothingQuality = 'high';
        contexto.drawImage(imagem, 0, 0, 1120, 630);
        return tela.toDataURL('image/webp', 0.78).split(',')[1];
    }, png.toString('base64'));
    writeFileSync(`/telas/${nome}.webp`, Buffer.from(webp, 'base64'));
    console.log(nome);
};
await ocioso();
await foto('resumo');
await abrir('/clientes');
await foto('clientes');
const ficha = await p.locator('.aba-raiz:visible .datagrid-row a').first().getAttribute('href');
await fechar();
await abrir(ficha);
await foto('ficha');
await fechar();
await abrir(`${ficha}/simulacao-de-acordo/nova`);
await p.locator('.textbox', { has: p.locator('input.textbox-value[name="agreement[installments]"]') }).locator('.combo-arrow').click();
await p.locator('.combobox-item:visible', { hasText: '6 parcelas' }).first().click();
await p.waitForTimeout(2200);
await foto('simulacao');
await fechar();
await abrir('/configuracao/segmentos');
await foto('segmentos');
await b.close();
