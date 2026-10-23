// V5 na demonstração (CRM_DEMO=1): como a do incremento 1, mas o arquivo enviado é trocado por um fictício, então os passos conferem
// que o arquivo de até 50 MB CHEGA (nginx, filtro de segurança, PHP e Livewire) e não o conteúdo dele. Incrementos 1 a 3.
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
    await pagina.getByText('Demonstração: os dados são fictícios').first().waitFor();
});

for (const [rota, texto] of [['/', 'Recuperado em'], ['/clientes', 'Clientes'], ['/importar', 'Importar carteira'], ['/importacoes', 'Importações de carteira'], ['/importar-pagamentos', 'Colunas da planilha'], ['/importar-estornos', 'identificador_estorno'], ['/pagamentos', 'Pagamentos e estornos'], ['/configuracao/canais', 'Canais de recebimento'], ['/configuracao/pagamentos', 'Políticas de pagamento e estorno'], ['/acionamentos', 'Acionamentos'], ['/configuracao/carteira', 'Políticas da carteira'], ['/configuracao/acionamentos', 'Resultados de acionamento']]) {
    await passo(`abrir ${rota}`, async () => {
        const resposta = await pagina.goto(BASE + rota);
        if (resposta.status() !== 200) throw new Error(`status ${resposta.status()}`);
        // Nas abas da configuração o nome também aparece na sub-navegação (e numa cópia escondida): confere o título da página.
        if (rota.startsWith('/configuracao')) {
            await pagina.getByRole('heading', { name: texto }).first().waitFor();
        } else {
            await pagina.getByText(texto).first().waitFor();
        }
        await pagina.screenshot({ path: `${PASTA}/${rota === '/' ? 'resumo' : rota.slice(1).replaceAll('/', '-')}.png` });
    });
}

// A recriação diária deixa uma importação conferida à espera: ela ocupa o credor (R10). Descarta para poder enviar.
await passo('descartar a importação conferida que a recriação deixa pendente', async () => {
    await pagina.goto(BASE + '/importacoes');
    const linha = pagina.locator('table tbody tr', { hasText: 'Conferida' }).first();
    if ((await linha.count()) === 0) return 'nenhuma pendente';
    await linha.click();
    await pagina.getByRole('button', { name: 'Descartar' }).waitFor();
    await pagina.click('button:has-text("Descartar")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Descartada').first().waitFor();
});

async function enviarArquivo(rota, arquivo, botao = 'Enviar e conferir') {
    await pagina.goto(BASE + rota);
    await pagina.setInputFiles('input[type=file]', arquivo);
    await pagina.locator('.filepond--item[data-filepond-item-state="processing-complete"]').waitFor({ timeout: 600000 });
    await pagina.click(`button:has-text("${botao}")`);
}

const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const { tamanho: tamanho50 } = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
const mb = (tamanho50 / 1048576).toFixed(1);

await passo(`carteira: enviar arquivo de ${mb} MB (trocado por fictício) e descartar a conferência`, async () => {
    await enviarArquivo('/importar', quase50);
    await pagina.waitForURL(/\/importacoes\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.getByText('arquivo-de-demonstracao.csv').first().waitFor();
    await pagina.click('button:has-text("Descartar")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Descartada').first().waitFor();
});

await passo(`pagamentos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e confirmar`, async () => {
    await enviarArquivo('/importar-pagamentos', quase50);
    await pagina.waitForURL(/\/pagamentos\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.screenshot({ path: `${PASTA}/pagamentos-conferencia.png` });
    await pagina.click('button:has-text("Confirmar importação")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Resultado', { exact: true }).first().waitFor({ timeout: 300000 });
});

await passo(`estornos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e descartar`, async () => {
    await enviarArquivo('/importar-estornos', quase50);
    await pagina.waitForURL(/\/pagamentos\/\d+/, { timeout: 300000 });
    await pagina.getByRole('button', { name: 'Confirmar importação' }).waitFor({ timeout: 300000 });
    await pagina.click('button:has-text("Descartar")');
    await pagina.click('.fi-modal-window button:has-text("Confirmar")');
    await pagina.getByText('Descartada').first().waitFor();
});

const acima = '/tmp/v5-acima.csv';
const { tamanho: tamanhoAcima } = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
for (const rota of ['/importar', '/importar-pagamentos']) {
    await passo(`recusar arquivo acima de 50 MB em ${rota} (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
        await pagina.goto(BASE + rota);
        await pagina.setInputFiles('input[type=file]', acima);
        await pagina.getByText(/50 MB|51200|maior que|tamanho/i).first().waitFor({ timeout: 120000 });
    });
}

await passo('acionamento: registrar pela ficha e anular', async () => {
    await pagina.goto(BASE + '/clientes');
    await pagina.locator('table tbody tr').first().click();
    await pagina.getByRole('button', { name: 'Registrar acionamento' }).click();
    await pagina.locator('.fi-modal-window select[id$="channel"]').selectOption({ label: 'Telefone' });
    await pagina.locator('.fi-modal-window select[id$="result_id"]').selectOption({ label: 'Não atendeu' });
    await pagina.locator('.fi-modal-window textarea[id$="text"]').fill('registrado na V5');
    await pagina.locator('.fi-modal-window button:has-text("Enviar")').click();
    await pagina.getByText('Acionamento registrado').first().waitFor();
    await pagina.getByRole('button', { name: 'Anular' }).first().click();
    await pagina.locator('.fi-modal-window textarea').fill('teste da V5');
    await pagina.locator('.fi-modal-window button:has-text("Enviar")').click();
    await pagina.getByText('Acionamento anulado').first().waitFor();
});

await passo('política de pagamento: mudar e desfazer', async () => {
    await pagina.goto(BASE + '/configuracao/pagamentos');
    await pagina.getByText('Crédito sem baixar:').click();
    await pagina.click('button:has-text("Salvar")');
    await pagina.getByText('Políticas salvas').first().waitFor();
    await pagina.goto(BASE + '/configuracao/pagamentos');
    await pagina.getByText('Baixa parcial:').click();
    await pagina.click('button:has-text("Salvar")');
    await pagina.getByText('Políticas salvas').first().waitFor();
});

await passo('canal de recebimento: criar e apagar', async () => {
    await pagina.goto(BASE + '/configuracao/canais/novo');
    await pagina.fill('input[id$="code"]', 'V5-TESTE');
    await pagina.fill('input[id$="description"]', 'Canal da V5');
    await pagina.getByRole('combobox', { name: /Tipo/ }).first().selectOption('account').catch(async () => {});
    await pagina.click('button:has-text("Criar")');
    await pagina.waitForURL(/\/configuracao\/canais\/\d+\/editar/);
    await pagina.goto(BASE + '/configuracao/canais');
    const linha = pagina.locator('table tbody tr', { hasText: 'V5-TESTE' });
    await linha.getByRole('button', { name: 'Apagar' }).click();
    await pagina.click('.fi-modal-window button:has-text("Excluir")');
    await pagina.getByText('V5-TESTE').first().waitFor({ state: 'detached' });
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado-demo.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
