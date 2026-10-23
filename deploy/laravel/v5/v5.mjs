// V5 do incremento 1 (estratégia de verificação do projeto): ponta a ponta contra o ambiente publicado, pelo caminho que o usuário
// usa. Entra, abre cada tela principal, envia a planilha no tamanho máximo (200.000 linhas e perto de 50 MB), confirma
// ou descarta, e muda e desfaz uma configuração. Também confirma que um arquivo acima de 50 MB é recusado.
//
//   BASE_URL=http://web:8080 V5_EMAIL=... V5_SENHA=... node v5.mjs
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync, statSync } from 'node:fs';

const BASE = process.env.BASE_URL ?? 'http://127.0.0.1:3210';
const EMAIL = process.env.V5_EMAIL;
const SENHA = process.env.V5_SENHA;
const PASTA = process.env.V5_TELAS ?? '/telas/v5';
mkdirSync(PASTA, { recursive: true });

const resultados = [];
const passo = async (nome, fn) => {
    const inicio = Date.now();
    try {
        const detalhe = await fn();
        resultados.push({ nome, ok: true, segundos: ((Date.now() - inicio) / 1000).toFixed(1), detalhe });
        console.log(`OK    ${nome} (${((Date.now() - inicio) / 1000).toFixed(1)} s) ${detalhe ?? ''}`);
    } catch (e) {
        await pagina.screenshot({ path: `${PASTA}/falha-${resultados.length + 1}.png` }).catch(() => {});
        resultados.push({ nome, ok: false, segundos: ((Date.now() - inicio) / 1000).toFixed(1), detalhe: String(e.message).split('\n')[0] });
        console.log(`FALHA ${nome}: ${String(e.message).split('\n')[0]}`);
    }
};

// Planilhas de teste: CPFs gerados com dígitos verificadores válidos.
function cpf(n) {
    const d = String(100000000 + ((n * 7919) % 899999999)).split('').map(Number);
    for (const len of [10, 11]) {
        let s = 0;
        d.forEach((x, i) => (s += x * (len - i)));
        d.push(((s * 10) % 11) % 10);
    }
    return d.join('');
}
function linha(i, descricao, hoje) {
    const dias = 1 + ((i * 37) % 500);
    const d = new Date(hoje.getTime() - (dias - 20) * 86400000);
    const data = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
    return [cpf(i), `Cliente Teste ${i}`, '', '', `CT-${String(i).padStart(7, '0')}`, `NF-${i}/1`, data, `${50 + (i % 2500)},00`, descricao].join(';');
}
// Gera até o número de linhas pedido, ou até o tamanho-alvo em bytes (o que vier primeiro).
function planilha(caminho, { linhas = Infinity, bytesAlvo = Infinity, descricao = 'Mensalidade' }) {
    const hoje = new Date();
    const partes = ['documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao'];
    let bytes = partes[0].length + 1;
    let i = 0;
    for (; i < linhas; i++) {
        const l = linha(i, descricao, hoje);
        if (bytes + l.length + 1 > bytesAlvo) break;
        partes.push(l);
        bytes += l.length + 1;
    }
    writeFileSync(caminho, partes.join('\n') + '\n');
    return { tamanho: statSync(caminho).size, linhas: i };
}

const navegador = await chromium.launch();
const contexto = await navegador.newContext({ viewport: { width: 1440, height: 900 } });
const pagina = await contexto.newPage();
pagina.setDefaultTimeout(60000);

await passo('entrar com e-mail e senha', async () => {
    await pagina.goto(BASE + '/login');
    await pagina.fill('#form\\.email', EMAIL);
    await pagina.fill('#form\\.password', SENHA);
    await pagina.click('button[type=submit]');
    await pagina.waitForURL(BASE + '/');
    await pagina.getByText('Resumo da carteira').first().waitFor();
});

for (const [rota, texto] of [['/', 'Resumo da carteira'], ['/clientes', 'Clientes'], ['/importar', 'Importar carteira'], ['/importacoes', 'Importações de carteira'], ['/configuracao', 'Configuração da carteira']]) {
    await passo(`abrir ${rota}`, async () => {
        const resposta = await pagina.goto(BASE + rota);
        if (resposta.status() !== 200) throw new Error(`status ${resposta.status()}`);
        await pagina.getByText(texto).first().waitFor();
        await pagina.screenshot({ path: `${PASTA}/${rota === '/' ? 'resumo' : rota.slice(1)}.png` });
    });
}

async function enviar(arquivo, modo) {
    await pagina.goto(BASE + '/importar');
    if (modo === 'batimento') await pagina.getByText('Batimento:').click();
    await pagina.setInputFiles('input[type=file]', arquivo);
    // O envio do arquivo ao servidor termina quando o campo chega a "processing-complete".
    await pagina.locator('.filepond--item[data-filepond-item-state="processing-complete"]').waitFor({ timeout: 600000 });
    await pagina.click('button:has-text("Enviar e conferir")');
}

const grande = '/tmp/v5-200mil.csv';
const { tamanho: tamanhoGrande } = planilha(grande, { linhas: 200000 });
await passo(`enviar 200.000 linhas (${(tamanhoGrande / 1048576).toFixed(1)} MB) e esperar a conferência`, async () => {
    const t = Date.now();
    await enviar(grande, 'incremental');
    await pagina.waitForURL(/\/importacoes\/\d+/, { timeout: 300000 });
    // O botão "Confirmar importação" só aparece com a conferência pronta (o texto "conferência" já aparece em "Em conferência").
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 600000 });
    await pagina.screenshot({ path: `${PASTA}/conferencia-200mil.png` });
    return `conferida em ${((Date.now() - t) / 1000).toFixed(0)} s, total, do envio à tela de resultado`;
});

await passo('confirmar a carga de 200.000 linhas', async () => {
    const t = Date.now();
    await pagina.click('button:has-text("Confirmar importação")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Resultado', { exact: true }).first().waitFor({ timeout: 600000 });
    return `confirmada em ${((Date.now() - t) / 1000).toFixed(0)} s`;
});

await passo('lista de clientes depois da carga (200.000 linhas)', async () => {
    const t = Date.now();
    await pagina.goto(BASE + '/clientes');
    await pagina.getByText('Cliente Teste').first().waitFor();
    await pagina.screenshot({ path: `${PASTA}/clientes-200mil.png` });
    return `aberta em ${((Date.now() - t) / 1000).toFixed(1)} s`;
});

// Perto do limite (49,5 MB) e logo acima dele (51 MB), com descrições longas para encher o arquivo com menos de 200.000 linhas.
const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const { tamanho: tamanho50, linhas: linhas50 } = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
await passo(`enviar arquivo perto de 50 MB (${(tamanho50 / 1048576).toFixed(1)} MB, ${linhas50} linhas) e descartar a conferência`, async () => {
    await enviar(quase50, 'incremental');
    await pagina.waitForURL(/\/importacoes\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 600000 });
    await pagina.click('button:has-text("Descartar")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Descartada').first().waitFor();
});

const acima = '/tmp/v5-acima.csv';
const { tamanho: tamanhoAcima } = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
await passo(`recusar arquivo acima de 50 MB (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
    await pagina.goto(BASE + '/importar');
    await pagina.setInputFiles('input[type=file]', acima);
    await pagina.getByText(/50 MB|51200|maior que|tamanho/i).first().waitFor({ timeout: 120000 });
    await pagina.screenshot({ path: `${PASTA}/arquivo-acima-do-limite.png` });
});

await passo('mudar a configuração e desfazer', async () => {
    await pagina.goto(BASE + '/configuracao');
    await pagina.getByText('Somado:').click();
    await pagina.click('button:has-text("Salvar")');
    await pagina.getByText('Configuração salva').first().waitFor();
    await pagina.goto(BASE + '/configuracao');
    await pagina.getByText('Separado:').click();
    await pagina.click('button:has-text("Salvar")');
    await pagina.getByText('Configuração salva').first().waitFor();
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
