// V5 na demonstração (CRM_DEMO=1), contra o ambiente publicado e pelo caminho que o usuário usa: entra com o usuário público, abre cada tela, envia arquivo
// de quase 50 MB nas três importações (o arquivo é trocado por um fictício, então o que se confere é que ele CHEGA: nginx, Thruster, Rails), recusa arquivo
// acima de 50 MB, registra um acionamento, aprova e recusa uma promessa pendente, aprova uma proposta de acordo e abre o termo, corrige um contato do
// cadastro, exporta os dados de um cliente, muda e desfaz uma política, cria e apaga um canal, confere o que a demonstração fecha, o link público de
// pagamento (sem login) e o isolamento do operador.
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
        await pagina.screenshot({ path: `${PASTA}/falha-${resultados.length + 1}.png` }).catch(() => {});
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
// As confirmações são <dialog role=alertdialog>: o botão de abrir está na página; o de confirmar, no rodapé do diálogo aberto.
const confirmar = async (abrir, acao) => {
    await pagina.getByRole('button', { name: abrir, exact: true }).first().click();
    await pagina.locator('dialog[open] footer').getByRole('button', { name: acao, exact: true }).click();
};
const h1 = (titulo) => pagina.getByRole('heading', { level: 1, name: titulo }).first();
const abrir = async (rota, titulo) => {
    const resposta = await pagina.goto(BASE + rota);
    if (resposta.status() !== 200) throw new Error(`${rota}: status ${resposta.status()}`);
    if (titulo) await h1(titulo).waitFor();
};

await passo('a tela de entrada mostra a faixa e os usuários da demonstração', async () => {
    await pagina.goto(BASE + '/session/new');
    await pagina.getByText('Demonstração: os dados são fictícios').first().waitFor();
    await pagina.getByText('demonstracao-gestor').first().waitFor();
});

await passo('entrar com e-mail e senha', async () => {
    await pagina.fill('#email_address', EMAIL);
    await pagina.fill('#password', SENHA);
    await pagina.click('button[type=submit]');
    await pagina.waitForURL(BASE + '/');
    await h1('Resumo da carteira').waitFor();
    await pagina.getByText('recriados todo dia às 04:00').first().waitFor();
});

const telas = [
    ['/', 'Resumo da carteira'], ['/clientes', 'Clientes'], ['/acionamentos', 'Acionamentos'], ['/importacoes/nova', 'Importar carteira'],
    ['/importacoes', 'Importações'], ['/importacoes/nova?kind=payments', 'Importar pagamentos'], ['/importacoes/nova?kind=reversals', 'Importar estornos'],
    ['/divergencias-de-valor', 'Divergências de valor'], ['/acordos', 'Acordos'], ['/acordos/pendentes', 'Acordos pendentes'], ['/promessas/pendentes', 'Promessas pendentes'],
    ['/estornos-a-espera', 'Estornos à espera do gestor'], ['/arquivo-de-acordos', 'Arquivo de acordos'], ['/guarda-de-dados', 'Guarda de dados'],
    ['/configuracao/dados-do-credor', 'Dados do credor'], ['/configuracao/carteira', 'Carteira'], ['/configuracao/canais-de-recebimento', 'Canais de recebimento'],
    ['/configuracao/politicas-de-pagamento', 'Políticas de pagamento'], ['/configuracao/contas-de-pagamento', 'Contas de pagamento'], ['/configuracao/segmentos', 'Segmentos'],
    ['/configuracao/promessas-e-acordos', 'Promessas e acordos'], ['/configuracao/indices', 'Índices do Banco Central'], ['/configuracao/resultados-de-acionamento', 'Resultados de acionamento'],
];
for (const [rota, titulo] of telas) {
    await passo(`abrir ${rota}`, async () => {
        await abrir(rota, titulo);
        await pagina.screenshot({ path: `${PASTA}/${rota === '/' ? 'resumo' : rota.slice(1).replace(/[/?=]/g, '-')}.png` });
    });
}

await passo('usuários e perfis ficam fechados (404) e a troca de senha é recusada com a mensagem da demonstração', async () => {
    for (const rota of ['/usuarios', '/perfis']) {
        const r = await pagina.goto(BASE + rota);
        if (r.status() !== 404) throw new Error(`${rota}: status ${r.status()}`);
    }
    await pagina.goto(BASE + '/senha/edit');
    await pagina.waitForURL(BASE + '/');
    await pagina.getByText('ficam fechados: dá para ver, não para alterar').first().waitFor();
});

await passo('contas de pagamento: a lista abre e a alteração é recusada', async () => {
    await abrir('/configuracao/contas-de-pagamento', 'Contas de pagamento');
    await pagina.getByText('fornecedor de demonstração').first().waitFor();
    await pagina.goto(BASE + '/configuracao/contas-de-pagamento/nova');
    await pagina.getByText('ficam fechados: dá para ver, não para alterar').first().waitFor();
});

// A recriação diária deixa uma importação conferida à espera: ela ocupa o credor (R10). Descarta para poder enviar.
await passo('descartar a importação conferida que a recriação deixa pendente', async () => {
    await abrir('/importacoes', 'Importações');
    const linha = pagina.locator('tbody tr', { hasText: 'Conferida' }).first();
    if ((await linha.count()) === 0) return 'nenhuma pendente';
    await linha.getByRole('link').first().click();
    await confirmar('Descartar', 'Descartar importação');
    await pagina.getByText('Descartada').first().waitFor();
});

async function enviarArquivo(rota, arquivo, esperaDestino = /\/importacoes\/\d+/) {
    await abrir(rota);
    await pagina.setInputFiles('input[type=file]', arquivo);
    await pagina.getByRole('button', { name: 'Enviar e conferir' }).click();
    await pagina.waitForURL(esperaDestino, { timeout: 600000 });
    await pagina.getByRole('button', { name: 'Confirmar', exact: true }).waitFor({ timeout: 300000 });
}

const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const tamanho50 = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
const mb = (tamanho50 / 1048576).toFixed(1);

await passo(`carteira: enviar arquivo de ${mb} MB (trocado por fictício) e descartar a conferência`, async () => {
    await enviarArquivo('/importacoes/nova', quase50);
    await pagina.getByText('arquivo-de-demonstracao.csv').first().waitFor();
    await confirmar('Descartar', 'Descartar importação');
    await pagina.getByText('Descartada').first().waitFor();
});

await passo(`pagamentos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e confirmar`, async () => {
    await enviarArquivo('/importacoes/nova?kind=payments', quase50);
    await pagina.screenshot({ path: `${PASTA}/pagamentos-conferencia.png` });
    await confirmar('Confirmar', 'Confirmar importação');
    await pagina.getByText('Confirmada').first().waitFor({ timeout: 300000 });
});

await passo(`estornos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e descartar`, async () => {
    await enviarArquivo('/importacoes/nova?kind=reversals', quase50);
    await confirmar('Descartar', 'Descartar importação');
    await pagina.getByText('Descartada').first().waitFor();
});

const acima = '/tmp/v5-acima.csv';
const tamanhoAcima = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
for (const rota of ['/importacoes/nova', '/importacoes/nova?kind=payments']) {
    await passo(`recusar arquivo acima de 50 MB em ${rota} (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
        await abrir(rota);
        await pagina.setInputFiles('input[type=file]', acima);
        await pagina.getByRole('button', { name: 'Enviar e conferir' }).click();
        await pagina.getByText(/acima do limite de 50 MB/i).first().waitFor({ timeout: 120000 });
    });
}

let fichaDoCliente;
await passo('acionamento: registrar pela ficha (o texto digitado vira texto fictício)', async () => {
    await abrir('/clientes', 'Clientes');
    await pagina.locator('tbody tr').first().getByRole('link').first().click();
    await pagina.waitForURL(/\/clientes\/\d+/);
    fichaDoCliente = pagina.url();
    await pagina.locator('#contact_attempt_channel').selectOption({ label: 'Telefone' });
    await pagina.locator('#contact_attempt_result_id').selectOption({ label: 'Não atendeu' });
    await pagina.locator('#contact_attempt_text').fill('Texto real do visitante, que não pode ficar guardado.');
    await pagina.getByRole('button', { name: 'Registrar acionamento', exact: true }).click();
    await pagina.getByText('texto descartado na demonstração').first().waitFor();
});

await passo('cadastro: o contato digitado é trocado por um fictício', async () => {
    await pagina.goto(fichaDoCliente);
    await pagina.locator('details#criar-contato > summary').click();
    await pagina.locator('#novo_contact_kind').selectOption('phone');
    await pagina.locator('#novo_contact_value').fill('(11) 98765-0000');
    await pagina.getByRole('button', { name: 'Criar contato', exact: true }).click();
    await pagina.waitForLoadState('networkidle');
    if (await pagina.getByText('98765-0000').count()) throw new Error('o contato digitado ficou guardado');
});

await passo('direitos do titular: exportar os dados de um cliente', async () => {
    await pagina.goto(fichaDoCliente);
    await pagina.getByRole('button', { name: 'Exportar dados', exact: true }).first().click();
    await pagina.locator('dialog[open] input[type=text]').fill('Pedido do titular, protocolo 1234');
    await pagina.locator('dialog[open]').getByRole('button', { name: 'Exportar dados', exact: true }).click();
    await pagina.waitForURL(/exportacao/);
    await pagina.getByText('motivo descartado').count();
});

await passo('promessas: aprovar uma pendente e recusar outra', async () => {
    await abrir('/promessas/pendentes', 'Promessas pendentes');
    const aprovar = pagina.getByRole('button', { name: 'Aprovar promessa' }).first();
    if ((await aprovar.count()) === 0) return 'nenhuma pendente';
    await aprovar.click();
    await pagina.getByText(/aprovad/i).first().waitFor();
    await abrir('/promessas/pendentes');
    const recusa = pagina.locator('details', { hasText: 'Recusar promessa' }).first();
    if ((await recusa.count()) === 0) return 'só uma pendente';
    await recusa.locator('summary').click();
    await recusa.locator('input[type=text]').fill('motivo real do visitante');
    await recusa.getByRole('button', { name: /Recusar promessa/ }).last().click();
    await pagina.getByText(/recusad/i).first().waitFor();
});

await passo('acordos: aprovar uma proposta pendente e abrir o termo de uma aprovada', async () => {
    await abrir('/acordos/pendentes', 'Acordos pendentes');
    const aprovar = pagina.getByRole('button', { name: /^Aprovar/ }).first();
    if ((await aprovar.count()) > 0) {
        await aprovar.click();
        await pagina.getByText(/aprovad/i).first().waitFor();
    }
    await abrir('/acordos', 'Acordos');
    const pagina_do_acordo = await pagina.locator('tr:has(th a[href^="/acordos/"]):has-text("Aprovad") th a').first().getAttribute('href');
    await pagina.goto(BASE + pagina_do_acordo);
    const termo = await pagina.getByRole('link', { name: 'Abrir o termo' }).first().getAttribute('href');
    await pagina.goto(BASE + termo);
    await pagina.getByText(/Escola Alfa/).first().waitFor();
});

await passo('política de pagamento: mudar e desfazer', async () => {
    await abrir('/configuracao/politicas-de-pagamento', 'Políticas de pagamento');
    const grupo = pagina.locator('fieldset', { hasText: 'Pagamento menor que o saldo' }).first();
    const marcado = await grupo.locator('input[type=radio]:checked').getAttribute('value');
    const outro = marcado === 'partial' ? 'credit' : 'partial';
    await grupo.locator(`input[value=${outro}]`).check();
    await pagina.getByRole('button', { name: 'Salvar políticas' }).first().click();
    await pagina.getByText(/salvas|salvos|atualizad/i).first().waitFor();
    await pagina.locator('fieldset', { hasText: 'Pagamento menor que o saldo' }).first().locator(`input[value=${marcado}]`).check();
    await pagina.getByRole('button', { name: 'Salvar políticas' }).first().click();
    await pagina.getByText(/salvas|salvos|atualizad/i).first().waitFor();
});

await passo('canal de recebimento: criar e apagar', async () => {
    await abrir('/configuracao/canais-de-recebimento/novo');
    await pagina.locator('#payment_channel_kind').selectOption({ label: 'Conta bancária' });
    await pagina.locator('#payment_channel_code').fill('V5-TESTE');
    await pagina.locator('#payment_channel_description').fill('Canal da V5');
    await pagina.getByRole('button', { name: 'Salvar', exact: true }).click();
    await abrir('/configuracao/canais-de-recebimento?q=V5-TESTE');
    const linha = pagina.locator('tbody tr', { hasText: 'V5-TESTE' });
    await linha.waitFor();
    await linha.getByRole('link').first().click();
    await pagina.waitForURL(/\/editar/);
    await confirmar('Apagar', 'Apagar canal');
    await pagina.waitForURL(/canais-de-recebimento$/);
    await abrir('/configuracao/canais-de-recebimento?q=V5-TESTE');
    if ((await pagina.locator('tbody tr', { hasText: 'V5-TESTE' }).count()) > 0) throw new Error('o canal continua na lista');
});

// O link de pagamento de exemplo: público (sem login), de outro contexto de navegador.
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
    await publico.screenshot({ path: `${PASTA}/pagar-cartao.png`, fullPage: true });
    await publico.context().close();
});

await passo('o operador só enxerga a Escola Alfa e não abre a configuração do credor', async () => {
    const outro = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })).newPage();
    outro.setDefaultTimeout(60000);
    await outro.goto(BASE + '/session/new');
    await outro.fill('#email_address', EMAIL.replace('gestor@', 'operador@'));
    await outro.fill('#password', 'demonstracao-operador');
    await outro.click('button[type=submit]');
    await outro.waitForURL(BASE + '/');
    await outro.locator('main').getByText('Escola Alfa').first().waitFor();
    if ((await outro.getByText('Clínica Beta').count()) > 0) throw new Error('o operador vê a Clínica Beta');
    const r = await outro.goto(BASE + '/configuracao/canais-de-recebimento');
    if (r.status() !== 404) throw new Error(`configuração respondeu ${r.status()}`);
    await outro.goto(BASE + '/clientes');
    if ((await outro.getByText('Clínica Beta').count()) > 0) throw new Error('o operador vê a Clínica Beta na lista');
    await outro.context().close();
});

await passo('o gestor vê os dois credores no resumo', async () => {
    await abrir('/', 'Resumo da carteira');
    await pagina.getByRole('heading', { name: 'Escola Alfa' }).first().waitFor();
    await pagina.getByRole('heading', { name: 'Clínica Beta' }).first().waitFor();
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado-demo.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
