// V5 na demonstração (CRM_DEMO=1), contra o ambiente publicado e pelo caminho que o usuário usa: entra com o usuário público,
// abre cada tela, envia arquivo de quase 50 MB nas três importações (o arquivo é trocado por um fictício, então o que se confere
// é que ele CHEGA: nginx, filtro de segurança, PHP e Livewire), recusa arquivo acima de 50 MB, registra e anula um acionamento,
// muda e desfaz uma política e cria e apaga um canal.
//
//   BASE_URL=https://crm.areacli.com V5_EMAIL=... V5_SENHA=... node v5-demo.mjs
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
function planilha(caminho, { bytesAlvo, descricao }) {
    const hoje = new Date();
    const partes = ['documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao'];
    let bytes = partes[0].length + 1;
    for (let i = 0; ; i++) {
        const dias = 1 + ((i * 37) % 500);
        const d = new Date(hoje.getTime() - (dias - 20) * 86400000);
        const data = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
        const linha = [cpf(i), `Cliente Teste ${i}`, '', '', `CT-${String(i).padStart(7, '0')}`, `NF-${i}/1`, data, `${50 + (i % 2500)},00`, descricao].join(';');
        if (bytes + linha.length + 1 > bytesAlvo) break;
        partes.push(linha);
        bytes += linha.length + 1;
    }
    writeFileSync(caminho, partes.join('\n') + '\n');
    return statSync(caminho).size;
}

const navegador = await chromium.launch();
const contexto = await navegador.newContext({ viewport: { width: 1440, height: 900 } });
const pagina = await contexto.newPage();
pagina.setDefaultTimeout(60000);
// As confirmações simples (wire:confirm) são diálogos do navegador: aceita todos.
pagina.on('dialog', (d) => d.accept());

await passo('entrar com e-mail e senha', async () => {
    await pagina.goto(BASE + '/login');
    await pagina.fill('#email', EMAIL);
    await pagina.fill('#password', SENHA);
    await pagina.click('button[type=submit]');
    await pagina.waitForURL(BASE + '/');
    await pagina.getByRole('heading', { name: 'Resumo da carteira' }).waitFor();
    await pagina.getByText('Demonstração: os dados são fictícios').first().waitFor();
});

const telas = [
    ['/', 'Resumo da carteira'], ['/clientes', 'Clientes'], ['/acionamentos', 'Acionamentos'], ['/importar', 'Importar carteira'],
    ['/importacoes', 'Importações de carteira'], ['/importar-pagamentos', 'Importar pagamentos'], ['/importar-estornos', 'Importar estornos'],
    ['/pagamentos', 'Pagamentos e estornos'], ['/configuracao/carteira', 'Configuração'], ['/configuracao/canais', 'Configuração'],
    ['/configuracao/pagamentos', 'Configuração'], ['/configuracao/acionamentos', 'Configuração'],
];
for (const [rota, titulo] of telas) {
    await passo(`abrir ${rota}`, async () => {
        const resposta = await pagina.goto(BASE + rota);
        if (resposta.status() !== 200) throw new Error(`status ${resposta.status()}`);
        await pagina.getByRole('heading', { name: titulo, exact: true }).first().waitFor();
        await pagina.screenshot({ path: `${PASTA}/${rota === '/' ? 'resumo' : rota.slice(1).replaceAll('/', '-')}.png` });
    });
}

// A recriação diária deixa uma importação conferida à espera: ela ocupa o credor (R10). Descarta para poder enviar.
await passo('descartar a importação conferida que a recriação deixa pendente', async () => {
    await pagina.goto(BASE + '/importacoes');
    const linha = pagina.locator('tbody tr', { hasText: 'Conferida' }).first();
    if ((await linha.count()) === 0) return 'nenhuma pendente';
    await linha.getByRole('link').first().click();
    await pagina.getByRole('button', { name: 'Descartar' }).click();
    await pagina.getByText('Descartada').first().waitFor();
});

async function enviarArquivo(rota, arquivo) {
    await pagina.goto(BASE + rota);
    // O envio ao servidor termina quando a rota de upload do Livewire responde.
    const enviado = pagina.waitForResponse((r) => r.url().includes('/upload-file') && r.request().method() === 'POST', { timeout: 600000 });
    await pagina.setInputFiles('input[type=file]', arquivo);
    await enviado;
    await pagina.getByRole('button', { name: 'Enviar e conferir' }).click();
}

const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const tamanho50 = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
const mb = (tamanho50 / 1048576).toFixed(1);

await passo(`carteira: enviar arquivo de ${mb} MB (trocado por fictício) e descartar a conferência`, async () => {
    await enviarArquivo('/importar', quase50);
    await pagina.waitForURL(/\/importacoes\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.getByText('arquivo-de-demonstracao.csv').first().waitFor();
    await pagina.getByRole('button', { name: 'Descartar' }).click();
    await pagina.getByText('Descartada').first().waitFor();
});

await passo(`pagamentos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e confirmar`, async () => {
    await enviarArquivo('/importar-pagamentos', quase50);
    await pagina.waitForURL(/\/pagamentos\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.screenshot({ path: `${PASTA}/pagamentos-conferencia.png` });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).click();
    await pagina.getByRole('heading', { name: 'Resultado' }).waitFor({ timeout: 300000 });
});

await passo(`estornos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e descartar`, async () => {
    await enviarArquivo('/importar-estornos', quase50);
    await pagina.waitForURL(/\/pagamentos\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.getByRole('button', { name: 'Descartar' }).click();
    await pagina.getByText('Descartada').first().waitFor();
});

const acima = '/tmp/v5-acima.csv';
const tamanhoAcima = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
for (const rota of ['/importar', '/importar-pagamentos']) {
    await passo(`recusar arquivo acima de 50 MB em ${rota} (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
        await pagina.goto(BASE + rota);
        await pagina.setInputFiles('input[type=file]', acima);
        await pagina.getByText(/kilobytes|50 MB|falhou|maior que|tamanho/i).first().waitFor({ timeout: 120000 });
    });
}

await passo('acionamento: registrar pela ficha e anular', async () => {
    await pagina.goto(BASE + '/clientes');
    await pagina.locator('tbody tr').first().getByRole('link').first().click();
    await pagina.getByRole('button', { name: 'Registrar acionamento' }).click();
    const janela = pagina.locator('[role=dialog]');
    await janela.locator('select[wire\\:model="channel"]').selectOption({ label: 'Telefone' });
    await janela.locator('select[wire\\:model\\.live="resultId"]').selectOption({ label: 'Não atendeu' });
    await janela.locator('textarea[wire\\:model="text"]').fill('registrado na V5');
    await janela.getByRole('button', { name: 'Registrar', exact: true }).click();
    await pagina.getByText('Acionamento registrado').first().waitFor();
    await pagina.getByRole('button', { name: 'Anular' }).first().click();
    await pagina.locator('textarea[wire\\:model="voidReason"]').fill('teste da V5');
    await pagina.locator('button[wire\\:click="void"]').click();
    await pagina.getByText('Acionamento anulado').first().waitFor();
});

await passo('política de pagamento: mudar e desfazer', async () => {
    await pagina.goto(BASE + '/configuracao/pagamentos');
    await pagina.getByText('Crédito sem baixar:').click();
    await pagina.getByRole('button', { name: 'Salvar' }).click();
    await pagina.getByText('Políticas salvas').first().waitFor();
    await pagina.getByText('Baixa parcial:').click();
    await pagina.getByRole('button', { name: 'Salvar' }).click();
    await pagina.getByText('Políticas salvas').nth(0).waitFor();
});

await passo('canal de recebimento: criar e apagar', async () => {
    await pagina.goto(BASE + '/configuracao/canais');
    await pagina.getByRole('button', { name: 'Novo canal' }).click();
    const janela = pagina.locator('[role=dialog]');
    await janela.locator('input[wire\\:model="code"]').fill('V5-TESTE');
    await janela.locator('input[wire\\:model="description"]').fill('Canal da V5');
    await janela.getByRole('button', { name: 'Salvar' }).click();
    const linha = pagina.locator('tbody tr', { hasText: 'V5-TESTE' });
    await linha.waitFor();
    await linha.getByRole('button', { name: 'Apagar' }).click();
    await linha.waitFor({ state: 'detached' });
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado-demo.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
