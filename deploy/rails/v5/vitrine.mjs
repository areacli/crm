// Fotos do carrossel da entrada da demonstração (`layouts/_vitrine`; padrões de interface, revisão 46): seis telas com os dados fictícios, cada uma
// recortada na parte que interessa, sem a faixa de aviso, em WebP de 2.160 × 1.280 (o dobro do tamanho em que aparecem, para o texto ler bem).
// Grava em /telas; copie os .webp para src/app/assets/images/vitrine.
//   deploy/rails/v5/v5.sh vitrine.mjs https://crm.areacli.com
// A foto da página de pagamento precisa do link de exemplo ainda sem pagar: rode depois da recriação das 4h e antes de qualquer V5 do dia.
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const BASE = process.env.BASE_URL ?? process.argv[2];
const LARGURA = 2160;
const ALTURA = 1280;
const b = await chromium.launch();

// Recorte em pixels da tela (x, y, largura); a altura sai da proporção do quadro (1.080 × 640).
const foto = async (pagina, nome, x, y, largura) => {
    const png = await pagina.screenshot({ clip: { x, y, width: largura, height: Math.round(largura * ALTURA / LARGURA) } });
    const webp = await pagina.evaluate(async ({ b64, LARGURA, ALTURA }) => {
        const imagem = new Image();
        imagem.src = `data:image/png;base64,${b64}`;
        await imagem.decode();
        const tela = Object.assign(document.createElement('canvas'), { width: LARGURA, height: ALTURA });
        const contexto = tela.getContext('2d');
        contexto.imageSmoothingQuality = 'high';
        contexto.drawImage(imagem, 0, 0, LARGURA, ALTURA);
        return tela.toDataURL('image/webp', 0.8).split(',')[1];
    }, { b64: png.toString('base64'), LARGURA, ALTURA });
    writeFileSync(`/telas/${nome}.webp`, Buffer.from(webp, 'base64'));
    console.log(nome);
};

// A casca com o menu recolhido, em 1.280 px: cabe a tela inteira, e o texto aparece maior do que numa foto da janela de 1.440.
const casca = async (largura) => {
    const p = await (await b.newContext({ viewport: { width: largura, height: 900 }, deviceScaleFactor: 2, ignoreHTTPSErrors: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' })).newPage();
    p.setDefaultTimeout(60000);
    await p.goto(`${BASE}/`);
    await p.fill('#entrada-email', process.env.V5_EMAIL);
    await p.fill('#entrada-senha', process.env.V5_SENHA);
    await p.click('#entrada-botao');
    await p.locator('#abas .tabs-title').first().waitFor();
    await p.click('#alternar-menu');
    return p;
};
const ocioso = async (p) => { await p.waitForTimeout(500); await p.waitForFunction(() => window.jQuery && jQuery.active === 0); await p.waitForTimeout(900); };
const abrir = async (p, url) => { await p.evaluate(async (u) => (await import('spa/abas')).abrir(u), url); await p.locator('.aba-raiz:visible').first().waitFor(); await ocioso(p); };
const fechar = (p) => p.evaluate(() => document.querySelector('#abas .tabs-selected .tabs-close')?.click());

// Régua: o diagrama de raias no desenho confortável, da primeira raia até a coluna D+30.
const larga = await casca(1380);
await abrir(larga, '/reguas');
const regua = await larga.locator('.aba-raiz:visible a[href^="/reguas/"]').evaluateAll((as) => as.map((a) => a.getAttribute('href')).find((h) => /^\/reguas\/\d+$/.test(h)));
await abrir(larga, regua);
await foto(larga, 'regua', 0, 24, 1380);

// Pagamento: a página pública do link de exemplo, do quadro do Pix ao do boleto, com os dados do instrumento e os dois "Copiar" (12, R280b).
const publica = await (await b.newContext({ viewport: { width: 1440, height: 1400 }, deviceScaleFactor: 2, ignoreHTTPSErrors: true, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' })).newPage();
await publica.goto(`${BASE}/pagar/demonstracao-pagamento`);
await publica.waitForTimeout(1500);
if (await publica.getByText('Pagamento no cartão aprovado').count()) {
    console.log('pagar: o link de exemplo já foi pago hoje; a foto ficou como estava (rode depois da recriação das 4h)');
} else {
    const quadro = (nome) => publica.locator('h2', { hasText: new RegExp(`^${nome}$`) }).evaluate((h) => {
        const caixa = h.closest('section, .cartao').getBoundingClientRect();
        return { topo: caixa.top, base: caixa.bottom, centro: caixa.left + caixa.width / 2 };
    });
    const pix = await quadro('Pix');
    const boleto = await quadro('Boleto');
    const largura = Math.round((boleto.base - pix.topo + 32) * LARGURA / ALTURA);
    await foto(publica, 'pagar', Math.max(0, Math.round(pix.centro - largura / 2)), Math.round(pix.topo - 16), largura);
}

const p = await casca(1280);
await ocioso(p);
await foto(p, 'resumo', 0, 24, 1280);
await abrir(p, '/clientes');
const ficha = await p.locator('.aba-raiz:visible .datagrid-row a').first().getAttribute('href');
await fechar(p);
await abrir(p, ficha);
await foto(p, 'ficha', 0, 24, 1280);
await fechar(p);
// Simulação: o cliente da demonstração pode ter títulos em dois sistemas; a tela pede o sistema antes (17, R412).
await abrir(p, `${ficha}/simulacao-de-acordo/nova`);
const sistemas = await p.locator('.aba-raiz:visible a[href*="sistema="]').evaluateAll((as) => as.map((a) => a.getAttribute('href')));
if (sistemas.length) { await fechar(p); await abrir(p, sistemas.at(-1)); }
await p.locator('.textbox', { has: p.locator('input.textbox-value[name="agreement[installments]"]') }).locator('.combo-arrow').click();
await p.locator('.combobox-item:visible', { hasText: '6 parcelas' }).first().click();
await p.waitForTimeout(2200);
await foto(p, 'simulacao', 0, 24, 1280);
await fechar(p);
await abrir(p, '/configuracao/segmentos');
await foto(p, 'segmentos', 0, 24, 1280);
await b.close();
