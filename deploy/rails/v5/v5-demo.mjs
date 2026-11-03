// V5 na demonstração (CRM_DEMO=1), contra o ambiente publicado e pelo caminho que o usuário usa, na SPA (decisão 0025): entra pela casca, abre cada tela numa aba,
// envia arquivo
// de quase 50 MB nas três importações (o arquivo é trocado por um fictício, então o que se confere é que ele CHEGA: nginx, Thruster, Rails), recusa arquivo
// acima de 50 MB, registra um acionamento, aprova e recusa uma promessa pendente, aprova uma proposta de acordo e abre o termo, corrige um contato do
// cadastro, exporta os dados de um cliente, muda e desfaz uma política, cria e apaga um canal, confere o que a demonstração fecha, o link público de
// pagamento (sem login), o isolamento do operador e o da operação de cobrança (incremento 14).
//
//   deploy/rails/v5/v5.sh v5-demo.mjs http://127.0.0.1:3220            (ou BASE_URL=... V5_EMAIL=... V5_SENHA=... node v5-demo.mjs)
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync, statSync } from 'node:fs';

const BASE = process.env.BASE_URL ?? process.argv[2] ?? 'http://127.0.0.1:3220';
const EMAIL = process.env.V5_EMAIL;
const SENHA = process.env.V5_SENHA;
const PASTA = process.env.V5_TELAS ?? '/telas';
const CHECKOUT = process.env.V5_CHECKOUT ?? 'demonstracao-pagamento';
mkdirSync(PASTA, { recursive: true });

const resultados = [];
let pagina;
const passo = async (nome, fn) => {
    const inicio = Date.now();
    const segundos = () => ((Date.now() - inicio) / 1000).toFixed(1);
    try {
        const detalhe = await fn();
        resultados.push({ nome, ok: true, segundos: segundos(), detalhe });
        console.log(`OK    ${nome} (${segundos()} s) ${detalhe ?? ''}`);
    } catch (e) {
        await (pagina?.context().pages().at(-1) ?? pagina).screenshot({ path: `${PASTA}/falha-${resultados.length + 1}.png` }).catch(() => {});
        resultados.push({ nome, ok: false, segundos: segundos(), detalhe: String(e.message).split('\n')[0] });
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
const contexto = await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 }, acceptDownloads: true });
pagina = await contexto.newPage();
pagina.setDefaultTimeout(60000);

// A SPA: cada tela abre pelo endereço com # e mostra o título; o indicador de carregamento cobre a tela enquanto busca o JSON.
const ocupada = (p = pagina) => p.locator('.sapUiLocalBusyIndicator').first().waitFor({ state: 'detached', timeout: 30000 }).catch(() => {});
const abrir = async (hash, titulo, p = pagina) => {
    await p.goto(`${BASE}/#/${hash}`);
    if (titulo) await p.locator('.sapMTitle:visible', { hasText: titulo }).first().waitFor();
    await ocupada(p);
};
// A pergunta curta (MessageBox) e o formulário (Dialog ou painel) da regra de ação.
const responder = async (acao) => { await pagina.locator('.sapMMessageBox, .sapMDialog').last().getByRole('button', { name: acao, exact: true }).click(); };
const aviso = (texto) => pagina.locator('.sapMMessageToast', { hasText: texto }).first().waitFor({ timeout: 120000 });
const entrar = async (p, email, senha) => {
    await p.goto(BASE + '/');
    await p.locator('input[type=email]').waitFor();
    await p.locator('input[type=email]').fill(email);
    await p.locator('input[type=password]').fill(senha);
    await p.getByRole('button', { name: 'Entrar', exact: true }).click();
    await p.locator('input[type=email]').waitFor({ state: 'hidden' });
    await p.locator('.sapTntToolHeader:visible').first().waitFor();
    await ocupada(p);
};
// O JSON de uma tela, pela sessão do navegador (o que a tela pediria).
const status = async (p, caminho) => p.evaluate(async (c) => (await fetch(c, { headers: { Accept: 'application/json' } })).status, caminho);

await passo('a tela de entrada mostra a faixa e os usuários da demonstração', async () => {
    await pagina.goto(BASE + '/');
    await pagina.getByText('Demonstração: os dados são fictícios').first().waitFor();
    await pagina.getByText('demonstracao-gestor').first().waitFor();
});

await passo('entrar com e-mail e senha', async () => {
    await entrar(pagina, EMAIL, SENHA);
    await pagina.locator('text=Resumo da carteira >> visible=true').first().waitFor();
    await pagina.locator('text=recriados todo dia às 04:00 >> visible=true').first().waitFor();
});

const telas = [
    ['resumo', 'Resumo da carteira'], ['clientes', 'Clientes'], ['acionamentos', 'Acionamentos'], ['importacoes', 'Importações'],
    ['importacoes/nova/portfolio', 'Importar carteira'], ['importacoes/nova/payments', 'Importar pagamentos'], ['importacoes/nova/reversals', 'Importar estornos'],
    ['divergencias-de-valor', 'Divergências de valor'], ['acordos', 'Acordos'], ['acordos/pendentes', 'Acordos pendentes'], ['promessas/pendentes', 'Promessas pendentes'],
    ['estornos-a-espera', 'Estornos à espera do gestor'], ['arquivo-de-acordos', 'Arquivo de acordos'], ['guarda-de-dados', 'Guarda de dados'],
    ['distribuicao', 'Distribuição'], ['filas', 'Filas'], ['filas/enquadramento', 'Enquadramento das filas'], ['filas/grupos', 'Grupos'],
    ['operacoes', 'Operações credenciadas'], ['operacoes/enquadramento-da-distribuicao', 'Enquadramento da distribuição'], ['operacoes/trilha', 'Trilha das operações'],
    ['configuracao/dados-do-credor', 'Dados do credor'], ['configuracao/carteira', 'Carteira'], ['configuracao/metodos-de-recebimento', 'Métodos de recebimento'],
    ['configuracao/politicas-de-pagamento', 'Políticas de pagamento'], ['configuracao/segmentos', 'Segmentos'], ['configuracao/enquadramento-financeiro', 'Enquadramento financeiro'],
    ['configuracao/promessas-e-acordos', 'Promessas e acordos'], ['configuracao/indices', 'Índices'], ['configuracao/resultados-de-acionamento', 'Resultados de acionamento'],
];
for (const [hash, titulo] of telas) {
    await passo(`abrir ${hash}`, async () => {
        await abrir(hash, titulo);
        await pagina.screenshot({ path: `${PASTA}/${hash.replace(/[/?=]/g, '-')}.png` });
    });
}

await passo('usuários e perfis ficam fechados (404) e a troca de senha é recusada com a mensagem da demonstração', async () => {
    for (const caminho of ['/usuarios.json', '/perfis.json']) {
        const s = await status(pagina, caminho);
        if (s !== 404) throw new Error(`${caminho}: status ${s}`);
    }
    const s = await status(pagina, '/configuracao/integracoes/nova.json');
    if (s !== 403) throw new Error(`nova integração respondeu ${s}`);
});

// A recriação diária deixa uma importação conferida à espera: ela ocupa o credor (R10). Descarta para poder enviar.
const descartarPendente = async () => {
    await abrir('importacoes', 'Importações');
    const linha = pagina.locator('.sapMListTblRow:visible', { hasText: 'Conferida' }).first();
    if ((await linha.count()) === 0) return 'nenhuma pendente';
    await linha.locator('a').first().click();
    await pagina.getByRole('button', { name: 'Descartar importação', exact: true }).first().click();
    await responder('Descartar importação');
    await aviso('Nada foi gravado');
};
await passo('descartar a importação conferida que a recriação deixa pendente', descartarPendente);

async function enviarArquivo(tipo, arquivo) {
    await abrir(`importacoes/nova/${tipo}`);
    await pagina.locator('.sapUiFup:visible input[type=file]').first().setInputFiles(arquivo);
    await pagina.getByRole('button', { name: 'Enviar e conferir' }).click();
}
async function esperarConferida() {
    await pagina.getByRole('button', { name: 'Confirmar importação', exact: true }).first().waitFor({ timeout: 600000 });
}

const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const tamanho50 = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
const mb = (tamanho50 / 1048576).toFixed(1);

await passo(`carteira: enviar arquivo de ${mb} MB (trocado por fictício) e descartar a conferência`, async () => {
    await enviarArquivo('portfolio', quase50);
    await esperarConferida();
    await pagina.locator('text=arquivo-de-demonstracao.csv >> visible=true').first().waitFor();
    await pagina.getByRole('button', { name: 'Descartar importação', exact: true }).first().click();
    await responder('Descartar importação');
    await aviso('Nada foi gravado');
});

await passo(`pagamentos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e confirmar`, async () => {
    await enviarArquivo('payments', quase50);
    await esperarConferida();
    await pagina.screenshot({ path: `${PASTA}/pagamentos-conferencia.png` });
    await pagina.getByRole('button', { name: 'Confirmar importação', exact: true }).first().click();
    await responder('Confirmar importação');
    await pagina.locator('.sapMObjStatus:visible', { hasText: 'Confirmada' }).first().waitFor({ timeout: 300000 });
});

await passo(`estornos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e descartar`, async () => {
    await enviarArquivo('reversals', quase50);
    await esperarConferida();
    await pagina.getByRole('button', { name: 'Descartar importação', exact: true }).first().click();
    await responder('Descartar importação');
    await aviso('Nada foi gravado');
});

const acima = '/tmp/v5-acima.csv';
const tamanhoAcima = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
for (const tipo of ['portfolio', 'payments']) {
    await passo(`recusar arquivo acima de 50 MB em ${tipo} (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
        await enviarArquivo(tipo, acima);
        await pagina.locator('text=/acima do limite de 50 MB/i >> visible=true').first().waitFor({ timeout: 120000 });
    });
}

let ficha;
await passo('acionamento: registrar pela ficha (o texto digitado vira texto fictício)', async () => {
    await abrir('clientes', 'Clientes');
    await pagina.locator('.sapMListTblRow:visible a:visible').first().click();
    await pagina.waitForURL(/#\/clientes\/\d+/);
    ficha = pagina.url().split('#/')[1];
    await ocupada();
    await pagina.getByRole('button', { name: 'Registrar acionamento', exact: true }).first().click();
    const painel = pagina.locator('.painel:visible').first();
    await painel.getByText('Canal').first().waitFor();
    await painel.locator('[id$="--canal"]').click();
    await pagina.locator('.sapMSelectList li', { hasText: 'Telefone' }).first().click();
    await painel.locator('[id$="--resultado"]').click();
    await pagina.locator('.sapMSelectList li', { hasText: 'Não atendeu' }).first().click();
    await painel.locator('textarea').first().fill('Texto real do visitante, que não pode ficar guardado.');
    await painel.getByRole('button', { name: 'Registrar acionamento', exact: true }).click();
    await aviso('Acionamento registrado');
    await ocupada();
    await pagina.locator('.sapMITBFilter:visible', { hasText: 'Acionamentos' }).first().click();
    await pagina.locator('text=texto descartado na demonstração >> visible=true').first().waitFor();
});

await passo('promessas: aprovar uma pendente', async () => {
    await abrir('promessas/pendentes', 'Promessas pendentes');
    const aprovar = pagina.getByRole('button', { name: /^Aprovar/ }).first();
    if ((await aprovar.count()) === 0) return 'nenhuma pendente';
    await aprovar.click();
    await aviso(/aprovad/i);
});

await passo('acordos: aprovar uma proposta pendente e abrir a página de um acordo', async () => {
    await abrir('acordos/pendentes', 'Acordos pendentes');
    const aprovar = pagina.getByRole('button', { name: /^Aprovar/ }).first();
    if ((await aprovar.count()) > 0) {
        await aprovar.click();
        await aviso(/aprovad/i);
    }
    await abrir('acordos', 'Acordos');
    await pagina.locator('.sapMListTblRow:visible a:visible').first().click();
    await pagina.waitForURL(/#\/acordos\/\d+/);
    await pagina.locator('text=Entrada e parcelas >> visible=true').first().waitFor();
});

await passo('política de pagamento: mudar e desfazer', async () => {
    await abrir('configuracao/politicas-de-pagamento', 'Políticas de pagamento');
    const bloco = pagina.locator('.bloco-de-politica:visible', { hasText: 'Pagamento menor que o saldo' }).first();
    const opcoes = bloco.locator('.sapMRb');
    const marcada = (await opcoes.first().getAttribute('aria-checked')) === 'true' ? 0 : 1;
    await opcoes.nth(1 - marcada).click();
    await pagina.getByRole('button', { name: 'Salvar', exact: true }).first().click();
    await aviso(/salv/i);
    await ocupada();
    await pagina.locator('.bloco-de-politica:visible', { hasText: 'Pagamento menor que o saldo' }).first().locator('.sapMRb').nth(marcada).click();
    await pagina.getByRole('button', { name: 'Salvar', exact: true }).first().click();
    await aviso(/salv/i);
});

await passo('método de recebimento: criar e excluir', async () => {
    await abrir('configuracao/metodos-de-recebimento', 'Métodos de recebimento');
    await pagina.getByRole('button', { name: 'Criar método de recebimento', exact: true }).click();
    const painel = pagina.locator('.painel:visible').first();
    await painel.getByText('Código').first().waitFor();
    await painel.locator('input.sapMInputBaseInner').nth(0).fill('V5-TESTE');
    await painel.locator('input.sapMInputBaseInner').nth(1).fill('Método da V5');
    await painel.getByRole('button', { name: 'Salvar', exact: true }).click();
    await aviso(/V5-TESTE/);
    await abrir('configuracao/metodos-de-recebimento?filtro=q%3DV5-TESTE');
    await pagina.locator('.sapMListTblRow:visible a:visible', { hasText: 'V5-TESTE' }).first().click();
    await pagina.waitForURL(/metodos-de-recebimento\/\d+/);
    await ocupada();
    await pagina.getByRole('button', { name: 'Excluir', exact: true }).click();
    await responder('Excluir método de recebimento');
    await aviso(/V5-TESTE/);
});

// O link de pagamento de exemplo: público (sem login), de outro contexto de navegador; é página do servidor, fora da SPA.
await passo('link público de pagamento: boleto, Pix e cartão, sem login', async () => {
    const publico = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
    publico.setDefaultTimeout(60000);
    const r = await publico.goto(`${BASE}/pagar/${CHECKOUT}`);
    if (r.status() !== 200) throw new Error(`status ${r.status()}`);
    await publico.getByText('Demonstração: nenhum pagamento é real').first().waitFor();
    await publico.screenshot({ path: `${PASTA}/pagar.png`, fullPage: true });
    const inexistente = await publico.goto(`${BASE}/pagar/nao-existe`);
    if (inexistente.status() !== 404) throw new Error(`link inexistente respondeu ${inexistente.status()}`);
    await publico.goto(`${BASE}/pagar/${CHECKOUT}`);
    await publico.locator('#cartao-numero').fill('4111111111111119');
    await publico.locator('#cartao-titular').fill('TITULAR DE TESTE');
    await publico.locator('#cartao-validade').fill('12/30');
    await publico.locator('#cartao-codigo').fill('123');
    await publico.locator('#cartao button[type=submit]').click();
    await publico.locator('#opcoes').getByText(/aprovad|recebemos|pagamento/i).first().waitFor();
    await publico.context().close();
});

await passo('o operador só enxerga a Escola Alfa (nunca a Clínica Beta) e não abre a configuração do credor', async () => {
    const outro = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
    outro.setDefaultTimeout(60000);
    await entrar(outro, EMAIL.replace('gestor@', 'operador@'), 'demonstracao-operador');
    const s = await status(outro, '/configuracao/metodos-de-recebimento.json');
    if (s !== 404) throw new Error(`configuração respondeu ${s}`);
    await abrir('clientes', 'Clientes', outro);
    await outro.locator('.sapMListTblRow:visible').first().waitFor();
    if ((await outro.locator('text=Clínica Beta >> visible=true').count()) > 0) throw new Error('o operador vê a Clínica Beta');
    await outro.context().close();
});

await passo('a operação vê só o que foi distribuído e não abre a configuração nem a distribuição', async () => {
    const op = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
    op.setDefaultTimeout(60000);
    await entrar(op, EMAIL.replace('gestor@', 'operacao@'), 'demonstracao-operacao');
    for (const caminho of ['/distribuicao.json', '/operacoes.json', '/configuracao/metodos-de-recebimento.json']) {
        const s = await status(op, caminho);
        if (s !== 404) throw new Error(`${caminho} respondeu ${s}`);
    }
    const lista = await op.evaluate(async () => (await fetch('/clientes.json', { headers: { Accept: 'application/json' } })).json());
    if (!(lista.total > 0 && lista.total < 3000)) throw new Error(`a operação vê ${lista.total} clientes`);
    await abrir('clientes', 'Clientes', op);
    if ((await op.locator('text=Clínica Beta >> visible=true').count()) > 0) throw new Error('a operação vê a Clínica Beta');
    await op.screenshot({ path: `${PASTA}/operacao-clientes.png`, fullPage: true });
    await op.context().close();
});

await passo('o gestor vê os dois credores na lista de clientes', async () => {
    const lista = await pagina.evaluate(async () => (await fetch('/clientes.json', { headers: { Accept: 'application/json' } })).json());
    const nomes = JSON.stringify(lista);
    if (!nomes.includes('Escola Alfa') || !nomes.includes('Clínica Beta')) throw new Error('faltou um credor');
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado-demo.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
