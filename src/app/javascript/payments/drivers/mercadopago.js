// Módulo do navegador do adaptador Mercado Pago (12, revisão 6, R284ab). Os campos de número, validade e código são quadros do próprio Mercado Pago
// (Secure Fields, `mp.fields`), montados no lugar dos nossos: o cartão não passa nem por este JavaScript. O que sai daqui para o servidor é só o token
// (`createCardToken`), o nome da bandeira e as parcelas. O SDK vem do domínio do Mercado Pago (o arquivo e os quadros são dele), e a política de conteúdo
// da página libera só os domínios que o adaptador declara. Documentação: mercadopago.com.br/developers, "Cartões" na API Orders e o README do sdk-js.
const CAMPOS = [
  ["cardNumber", "#cartao-numero", "mp-cartao-numero"],
  ["expirationDate", "#cartao-validade", "mp-cartao-validade"],
  ["securityCode", "#cartao-codigo", "mp-cartao-codigo"],
]

let carregando
let mp

function carregarSdk(config) {
  if (window.MercadoPago) return Promise.resolve(window.MercadoPago)
  carregando ??= new Promise((resolver, recusar) => {
    const script = document.createElement("script")
    script.src = config.sdk_url
    script.onload = () => (window.MercadoPago ? resolver(window.MercadoPago) : recusar({ reason: "script_blocked" }))
    script.onerror = () => recusar({ reason: "script_blocked" })
    document.head.append(script)
  })
  return carregando
}

// Monta os quadros do Mercado Pago no lugar dos campos de número, validade e código, que ficam escondidos e deixam de ser obrigatórios.
export async function mount(_library, config, form, { bandeira }) {
  const MercadoPago = await carregarSdk(config)
  mp ??= new MercadoPago(config.public_key, { locale: "pt-BR" })
  const campos = {}
  for (const [tipo, seletor, id] of CAMPOS) {
    const nosso = form.querySelector(seletor)
    nosso.required = false
    nosso.hidden = true
    const caixa = document.createElement("div")
    caixa.id = id
    caixa.dataset.campoDoFornecedor = ""
    nosso.after(caixa)
    campos[tipo] = mp.fields.create(tipo, { placeholder: nosso.placeholder || "" }).mount(id)
  }
  // A bandeira vem do Mercado Pago pelos primeiros dígitos, dentro do quadro; só o nome dela segue.
  campos.cardNumber.on("binChange", async ({ bin }) => {
    if (!bin) return
    const { results } = await mp.getPaymentMethods({ bin })
    const id = results?.[0]?.id
    if (id) bandeira(id)
  })
}

export async function brand() {
  return null
}

export async function tokenize(_library, _config, card) {
  if (!mp) throw { reason: "script_blocked" }
  try {
    const token = await mp.fields.createCardToken({ cardholderName: card.holderName })
    if (!token?.id) throw { reason: "form_error" }
    return token.id
  } catch (erro) {
    if (erro?.reason) throw erro
    throw { reason: "form_error" }
  }
}
