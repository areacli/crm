// V5 na demonstração (CRM_DEMO=1), contra o ambiente publicado e pelo caminho que o usuário usa, na casca da SPA em EasyUI (decisão 0028; fase 8 do port):
// entra com o usuário público, abre cada tela numa aba, envia arquivo de quase 50 MB nas três importações (o arquivo é trocado por um fictício, então o que se
// confere é que ele CHEGA: nginx, Thruster, Rails), recusa arquivo acima de 50 MB, registra um acionamento, aprova e recusa uma promessa pendente, aprova uma
// proposta de acordo e abre o termo, cria um contato, exporta os dados de um cliente, muda e desfaz uma política, cria e exclui um método de recebimento,
// confere o que a demonstração fecha, o link público de pagamento (sem login), o isolamento do operador e o da operação de cobrança.
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
const novaPagina = async () => {
    const p = await (await navegador.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 }, acceptDownloads: true })).newPage();
    p.setDefaultTimeout(60000);
    return p;
};
pagina = await novaPagina();

// Peças da casca: entrar, abrir uma aba pelo endereço (como o menu), a raiz da aba visível, os pedidos do jQuery terminados, o diálogo e o aviso do canto.
const entrar = async (p, email, senha) => {
    await p.goto(BASE + '/');
    await p.locator('#entrada:not([hidden])').waitFor();
    await p.fill('#entrada-email', email);
    await p.fill('#entrada-senha', senha);
    await p.click('#entrada-botao');
    await p.locator('#abas .tabs-title').first().waitFor();
};
const ocioso = async (p = pagina) => {
    await p.waitForTimeout(400);
    await p.waitForFunction(() => window.jQuery && jQuery.active === 0, null, { timeout: 60000 });
    await p.waitForTimeout(300);
};
const raiz = (p = pagina) => p.locator('.aba-raiz:visible').first();
const aba = async (rota, titulo, p = pagina) => {
    await p.evaluate(async (url) => (await import('spa/abas')).abrir(url), rota);
    await ocioso(p);
    if (titulo) await raiz(p).locator('h1', { hasText: titulo }).first().waitFor();
};
const falhaNaAba = async (rota, p = pagina) => {
    await aba(rota, null, p);
    await raiz(p).locator('.falha', { hasText: 'Não encontrado' }).first().waitFor();
};
const dialogo = () => pagina.locator('.dialogo-conteudo form.dialogo').last();
const gravarDialogo = async (botao) => {
    await dialogo().locator('footer').getByRole('button', { name: botao, exact: true }).click();
    await pagina.locator('.dialogo-conteudo form.dialogo').waitFor({ state: 'detached', timeout: 120000 }).catch(() => {});
    await ocioso();
};
const confirmar = async (abrir, acao) => {
    await raiz().locator('a.botao', { hasText: abrir }).first().click();
    await dialogo().waitFor();
    await gravarDialogo(acao);
};
const aviso = (texto) => pagina.locator('.messager-body', { hasText: texto }).first().waitFor();
const escolher = async (rotulo, opcao) => {
    await dialogo().locator('.campo', { hasText: rotulo }).first().locator('.combo-arrow').click();
    await pagina.locator('.combobox-item:visible', { hasText: opcao }).first().click();
    await ocioso();
};
const maisAcoes = async (item) => {
    await raiz().locator('.cabecalho-da-pagina .menu-de-linha').first().click();
    await pagina.locator('[popover]:popover-open').locator('a, button', { hasText: item }).first().click();
};
const total = async (p = pagina) => Number(((await raiz(p).locator('.pagination-info').first().textContent()) ?? '').match(/de ([\d.]+)/)?.[1]?.replace(/\./g, '') ?? NaN);

await passo('a entrada da casca mostra os usuários da demonstração', async () => {
    await pagina.goto(BASE + '/');
    await pagina.locator('.entrada-demonstracao').getByText('demonstracao-gestor').first().waitFor();
});

await passo('entrar com e-mail e senha, com a faixa da demonstração no alto', async () => {
    await entrar(pagina, EMAIL, SENHA);
    await raiz().locator('h1', { hasText: 'Resumo da carteira' }).first().waitFor();
    await pagina.locator('#norte .faixa', { hasText: 'Demonstração: os dados são fictícios' }).waitFor();
    await ocioso();
    await pagina.screenshot({ path: `${PASTA}/resumo.png` });
    if (await pagina.locator('#sem-conexao:not([hidden])').count()) throw new Error('a casca mostra a conexão caída');
});

const telas = [
    ['/clientes', 'Clientes'], ['/acionamentos', 'Acionamentos'], ['/importacoes/nova', 'Importar carteira'], ['/importacoes', 'Importações'],
    ['/importacoes/nova?tipo=pagamentos', 'Importar pagamentos'], ['/importacoes/nova?tipo=estornos', 'Importar estornos'], ['/divergencias-de-valor', 'Divergências de valor'],
    ['/acordos', 'Acordos'], ['/acordos/pendentes', 'Acordos pendentes'], ['/promessas/pendentes', 'Promessas pendentes'], ['/estornos-a-espera', 'Estornos à espera do gestor'],
    ['/arquivo-de-acordos', 'Arquivo de acordos'], ['/distribuicao', 'Distribuição'], ['/filas', 'Filas'], ['/operacoes', 'Operações credenciadas'], ['/guarda-de-dados', 'Guarda de dados'],
    ['/configuracao/dados-do-credor', 'Dados do credor'], ['/configuracao/carteira', 'Carteira'], ['/configuracao/metodos-de-recebimento', 'Métodos de recebimento'],
    ['/configuracao/politicas-de-pagamento', 'Políticas de pagamento'], ['/configuracao/segmentos', 'Segmentos'], ['/configuracao/enquadramento-financeiro', 'Enquadramento financeiro'],
    ['/configuracao/promessas-e-acordos', 'Promessas e acordos'], ['/configuracao/indices', 'Índices do Banco Central'], ['/configuracao/resultados-de-acionamento', 'Resultados de acionamento'],
];
for (const [rota, titulo] of telas) {
    await passo(`abrir ${rota} numa aba`, async () => {
        await aba(rota, titulo);
        await pagina.screenshot({ path: `${PASTA}/${rota.slice(1).replace(/[/?=]/g, '-')}.png` });
        await pagina.evaluate(() => document.querySelector('#abas .tabs-selected .tabs-close')?.click());
    });
}

await passo('usuários e perfis ficam fechados (não encontrado) e a troca de senha some do menu e fica fechada', async () => {
    for (const rota of ['/usuarios', '/perfis']) await falhaNaAba(rota);
    const menu = await pagina.evaluate(async () => (await fetch('/menu.json')).json());
    if (menu.trocar_senha !== false) throw new Error('o menu oferece a troca de senha');
    const html = await pagina.evaluate(async () => (await fetch('/senha/editar', { headers: { 'X-CRM-Trecho': '1' } })).text());
    if (!html.includes('Fechado na demonstração')) throw new Error('a troca de senha não está fechada');
});

await passo('integrações: a lista abre no detalhe dos métodos de recebimento e a nova integração fica fechada', async () => {
    await aba('/configuracao/metodos-de-recebimento', 'Métodos de recebimento');
    await raiz().locator(".datagrid-header [aria-label='Mostrar os detalhes de todas as linhas']").first().click();
    await raiz().getByText('fornecedor de demonstração').first().waitFor();
    await aba('/configuracao/integracoes/nova', 'Fechado na demonstração');
});

// A recriação diária deixa uma importação conferida à espera: ela ocupa o credor (R10). Descarta para poder enviar.
await passo('descartar a importação conferida que a recriação deixa pendente', async () => {
    await aba('/importacoes', 'Importações');
    const linha = raiz().locator('.datagrid-row', { hasText: 'Conferida' }).first();
    if ((await linha.count()) === 0) return 'nenhuma pendente';
    await linha.locator('a').first().click();
    await ocioso();
    await confirmar('Descartar', 'Descartar importação');
    await raiz().getByText('Descartada').first().waitFor();
});

// O envio sai da aba da importação nova e abre a aba da importação, que mostra a conferência pelo tempo real.
async function enviarArquivo(rota, titulo, arquivo) {
    await aba(rota, titulo);
    await raiz().locator('input[type=file]').setInputFiles(arquivo);
    await raiz().getByRole('button', { name: 'Enviar e conferir' }).click();
    await raiz().locator('h1', { hasText: 'Importação de' }).first().waitFor({ timeout: 600000 });
    await raiz().locator('a.botao', { hasText: 'Confirmar' }).first().waitFor({ timeout: 300000 });
}

const quase50 = '/tmp/v5-50mb.csv';
const descricaoLonga = 'x'.repeat(290);
const tamanho50 = planilha(quase50, { bytesAlvo: Math.floor(49.5 * 1048576), descricao: descricaoLonga });
const mb = (tamanho50 / 1048576).toFixed(1);

await passo(`carteira: enviar arquivo de ${mb} MB (trocado por fictício) e descartar a conferência`, async () => {
    await enviarArquivo('/importacoes/nova', 'Importar carteira', quase50);
    await raiz().getByText('arquivo-de-demonstracao.csv').first().waitFor();
    await confirmar('Descartar', 'Descartar importação');
    await raiz().getByText('Descartada').first().waitFor();
});

await passo(`pagamentos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e confirmar`, async () => {
    await enviarArquivo('/importacoes/nova?tipo=pagamentos', 'Importar pagamentos', quase50);
    await pagina.screenshot({ path: `${PASTA}/pagamentos-conferencia.png` });
    await confirmar('Confirmar', 'Confirmar importação');
    await raiz().getByText('Confirmada').first().waitFor({ timeout: 300000 });
});

await passo(`estornos: enviar arquivo de ${mb} MB (trocado por fictício), conferir e descartar`, async () => {
    await enviarArquivo('/importacoes/nova?tipo=estornos', 'Importar estornos', quase50);
    await confirmar('Descartar', 'Descartar importação');
    await raiz().getByText('Descartada').first().waitFor();
});

const acima = '/tmp/v5-acima.csv';
const tamanhoAcima = planilha(acima, { bytesAlvo: 51 * 1048576, descricao: descricaoLonga });
for (const [rota, titulo] of [['/importacoes/nova', 'Importar carteira'], ['/importacoes/nova?tipo=pagamentos', 'Importar pagamentos']]) {
    await passo(`recusar arquivo acima de 50 MB em ${rota} (${(tamanhoAcima / 1048576).toFixed(1)} MB)`, async () => {
        await aba(rota, titulo);
        await raiz().locator('input[type=file]').setInputFiles(acima);
        await raiz().getByRole('button', { name: 'Enviar e conferir' }).click();
        await raiz().getByText(/acima do limite de 50 MB/i).first().waitFor({ timeout: 120000 });
    });
}

let fichaDoCliente;
await passo('acionamento: registrar pela ficha (o texto digitado vira texto fictício)', async () => {
    await aba('/clientes', 'Clientes');
    await raiz().locator('.datagrid-row a').first().click();
    await ocioso();
    fichaDoCliente = await pagina.evaluate(() => location.hash.slice(1).split('?')[0]);
    await raiz().locator('a.botao', { hasText: 'Registrar acionamento' }).first().click();
    await dialogo().waitFor();
    await escolher('Canal', 'Telefone');
    await escolher('Resultado', 'Não atendeu');
    await dialogo().locator('textarea').first().fill('Texto real do visitante, que não pode ficar guardado.');
    await gravarDialogo('Registrar acionamento');
    await aviso('Acionamento registrado');
    await aba(`${fichaDoCliente}?aba=acionamentos`);
    await raiz().getByText('texto descartado na demonstração').first().waitFor();
});

await passo('cadastro: o contato digitado é trocado por um fictício', async () => {
    await aba(fichaDoCliente);
    await maisAcoes('Criar contato');
    await dialogo().waitFor();
    await escolher('Tipo', 'Telefone');
    await dialogo().locator('input[name="contact[value]"]').fill('(11) 98765-0000');
    await gravarDialogo('Criar contato');
    await aba(`${fichaDoCliente}?aba=contatos`);
    if (await raiz().getByText('98765-0000').count()) throw new Error('o contato digitado ficou guardado');
});

await passo('direitos do titular: exportar os dados de um cliente (abre para imprimir)', async () => {
    await aba(fichaDoCliente);
    await maisAcoes('Exportar dados');
    await dialogo().locator('input[type=text], textarea').first().fill('Pedido do titular, protocolo 1234');
    await gravarDialogo('Exportar dados');
    // O navegador só abre a janela com um clique: o aviso traz o link para a página para imprimir.
    const link = pagina.locator('.messager-body a', { hasText: 'Abrir a página para imprimir' });
    const impressao = pagina.context().waitForEvent('page');
    await link.click();
    const nova = await impressao;
    await nova.waitForURL(/exportacao/);
    await nova.locator('h1', { hasText: /Dados de/ }).waitFor();
    await nova.close();
    await pagina.locator('.messager-window .messager-button a', { hasText: 'Ok' }).click();
});

await passo('promessas: aprovar uma pendente e recusar outra', async () => {
    await aba('/promessas/pendentes', 'Promessas pendentes');
    const aprovar = raiz().getByRole('button', { name: /^Aprovar promessa/ }).first();
    if ((await aprovar.count()) === 0) return 'nenhuma pendente';
    await aprovar.click();
    await aviso(/aprovad/i);
    await ocioso();
    const menu = raiz().locator('.datagrid-row .menu-de-linha').first();
    if ((await menu.count()) === 0) return 'só uma pendente';
    await menu.click();
    await pagina.locator('[popover]:popover-open').locator('a', { hasText: 'Recusar promessa' }).first().click();
    await dialogo().locator('input[type=text], textarea').first().fill('motivo real do visitante');
    await gravarDialogo('Recusar promessa');
    await aviso(/recusad/i);
});

await passo('acordos: aprovar uma proposta pendente e abrir o termo de uma aprovada', async () => {
    await aba('/acordos/pendentes', 'Acordos pendentes');
    const aprovar = raiz().getByRole('button', { name: /^Aprovar proposta/ }).first();
    if ((await aprovar.count()) > 0) {
        await aprovar.click();
        await aviso(/aprovad/i);
    }
    await aba('/acordos', 'Acordos');
    await raiz().locator('.datagrid-row', { hasText: 'Aprovad' }).first().locator('a[href^="/acordos/"]').first().click();
    await raiz().locator('h1', { hasText: 'Acordo' }).first().waitFor();
    const termo = pagina.context().waitForEvent('page');
    await raiz().locator('a.botao', { hasText: 'Abrir o termo' }).first().click();
    const nova = await termo;
    await nova.getByText(/Escola Alfa/).first().waitFor();
    await nova.close();
});

await passo('política de pagamento: mudar e desfazer', async () => {
    await aba('/configuracao/politicas-de-pagamento', 'Políticas de pagamento');
    const grupo = () => raiz().locator('.politica', { hasText: 'Pagamento menor que o saldo' }).first();
    const marcado = await grupo().locator('input[type=radio]:checked').getAttribute('value');
    const outro = marcado === 'partial' ? 'credit' : 'partial';
    await grupo().locator(`input[value=${outro}]`).check();
    await raiz().getByRole('button', { name: 'Salvar políticas' }).first().click();
    await aviso(/salvas|salvos|atualizad/i);
    await ocioso();
    await grupo().locator(`input[value=${marcado}]`).check();
    await raiz().getByRole('button', { name: 'Salvar políticas' }).first().click();
    await aviso(/salvas|salvos|atualizad/i);
});

await passo('método de recebimento: criar e excluir', async () => {
    await aba('/configuracao/metodos-de-recebimento', 'Métodos de recebimento');
    await raiz().locator('.cabecalho-da-pagina a.botao', { hasText: 'Criar método de recebimento' }).click();
    await dialogo().waitFor();
    await escolher('Tipo', 'Conta bancária');
    await dialogo().locator('input[name="payment_channel[code]"]').fill('V5-TESTE');
    await dialogo().locator('input[name="payment_channel[description]"]').fill('Método da V5');
    await gravarDialogo('Salvar');
    await raiz().locator('.datagrid-row a', { hasText: 'V5-TESTE' }).first().click();
    await raiz().locator('h1', { hasText: 'Método V5-TESTE' }).first().waitFor();
    await confirmar('Excluir', 'Excluir método de recebimento');
    await raiz().locator('h1', { hasText: 'Métodos de recebimento' }).first().waitFor();
    if ((await raiz().locator('.datagrid-row', { hasText: 'V5-TESTE' }).count()) > 0) throw new Error('o método de recebimento continua na lista');
});

// O link de pagamento de exemplo: público (sem login), de outro contexto de navegador; segue página do servidor.
await passo('link público de pagamento: boleto, Pix e cartão, sem login', async () => {
    const publico = await novaPagina();
    const r = await publico.goto(`${BASE}/pagar/${CHECKOUT}`);
    if (r.status() !== 200) throw new Error(`status ${r.status()}`);
    await publico.getByText('Demonstração: nenhum pagamento é real').first().waitFor();
    await publico.screenshot({ path: `${PASTA}/pagar.png`, fullPage: true });
    const inexistente = await publico.goto(`${BASE}/pagar/nao-existe`);
    if (inexistente.status() !== 404) throw new Error(`link inexistente respondeu ${inexistente.status()}`);
    await publico.goto(`${BASE}/pagar/${CHECKOUT}`);
    // O cartão do link de exemplo só se paga uma vez por dia (volta na recriação das 4h): numa segunda rodada, confere que a página mostra o pagamento já feito.
    if ((await publico.locator('#cartao-numero').count()) === 0) {
        await publico.locator('#opcoes').getByText(/aprovad/i).first().waitFor();
        await publico.context().close();
        return 'cartão já pago hoje';
    }
    await publico.locator('#cartao-numero').fill('4111111111111119');
    await publico.locator('#cartao-titular').fill('TITULAR DE TESTE');
    await publico.locator('#cartao-validade').fill('12/30');
    await publico.locator('#cartao-codigo').fill('123');
    await publico.locator('#cartao button[type=submit]').click();
    await publico.locator('#opcoes').getByText(/aprovad|recebemos|pagamento/i).first().waitFor();
    await publico.screenshot({ path: `${PASTA}/pagar-cartao.png`, fullPage: true });
    await publico.context().close();
});

await passo('o operador só enxerga a Escola Alfa (nunca a Clínica Beta) e não abre a configuração do credor', async () => {
    const outro = await novaPagina();
    await entrar(outro, EMAIL.replace('gestor@', 'operador@'), 'demonstracao-operador');
    await raiz(outro).locator('h1', { hasText: 'Resumo da carteira' }).first().waitFor();
    if ((await outro.getByText('Clínica Beta').count()) > 0) throw new Error('o operador vê a Clínica Beta');
    await falhaNaAba('/configuracao/metodos-de-recebimento', outro);
    await aba('/clientes', 'Clientes', outro);
    await raiz(outro).locator('.datagrid-row').first().waitFor();
    if ((await outro.getByText('Clínica Beta').count()) > 0) throw new Error('o operador vê a Clínica Beta na lista');
    await outro.context().close();
});

await passo('a operação vê o nome dela no cabeçalho, só o que foi distribuído, e não abre a configuração nem a distribuição', async () => {
    const op = await novaPagina();
    await entrar(op, EMAIL.replace('gestor@', 'operacao@'), 'demonstracao-operacao');
    await op.locator('#operacao-atual:not([hidden])', { hasText: 'Recupera' }).waitFor();
    for (const rota of ['/distribuicao', '/operacoes', '/configuracao/metodos-de-recebimento']) await falhaNaAba(rota, op);
    await aba('/clientes', 'Clientes', op);
    await raiz(op).locator('.datagrid-row').first().waitFor();
    const n = await total(op);
    if (!(n > 0 && n < 3000)) throw new Error(`a operação vê ${n} clientes`);
    if ((await op.getByText('Clínica Beta').count()) > 0) throw new Error('a operação vê a Clínica Beta');
    await op.screenshot({ path: `${PASTA}/operacao-clientes.png`, fullPage: true });
    await op.context().close();
    return `${n} clientes`;
});

await passo('o gestor vê os dois credores (o resumo é um conjunto de totais; os credores aparecem no filtro da lista de clientes)', async () => {
    await aba('/resumo', 'Resumo da carteira');
    if ((await raiz().getByRole('heading', { name: 'Escola Alfa' }).count()) > 0) throw new Error('o resumo voltou a quebrar por credor');
    await aba('/clientes', 'Clientes');
    await raiz().locator('.campo', { hasText: 'Credor' }).first().locator('.combo-arrow').click();
    const credores = (await pagina.locator('.combobox-item:visible').allTextContents()).map((t) => t.trim());
    await pagina.keyboard.press('Escape');
    for (const nome of ['Escola Alfa', 'Clínica Beta']) if (!credores.includes(nome)) throw new Error(`o filtro não traz ${nome}`);
});

await navegador.close();
const falhas = resultados.filter((r) => !r.ok);
console.log(`\nV5: ${resultados.length - falhas.length} de ${resultados.length} passos passaram.`);
writeFileSync(`${PASTA}/resultado-demo.json`, JSON.stringify(resultados, null, 2));
process.exit(falhas.length ? 1 : 0);
