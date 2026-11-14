// Módulo do navegador do adaptador PagBank (12, revisão 5, R284t). O SDK do PagBank (script clássico, servido do nosso domínio, com integridade conferida)
// cifra o cartão aqui, com a chave pública da conta e sem chamada de rede; o que sai para o servidor é só o cartão cifrado, que o servidor não consegue abrir.
// Número, validade e código nunca saem deste navegador em claro. A bandeira sai dos primeiros dígitos, aqui mesmo, e só o nome dela vai ao servidor.
// Documentação: developer.pagbank.com.br, "Criar e pagar pedido com cartão" (`PagSeguro.encryptCard`).
const BRANDS = [
  ["elo", /^(401178|401179|431274|438935|451416|457393|457631|457632|504175|506699|5067|509|627780|636297|636368|650|6516|6550)/],
  ["hipercard", /^(606282|3841)/],
  ["amex", /^3[47]/],
  ["visa", /^4/],
  ["mastercard", /^(5[1-5]|2(2[2-9]|[3-6]|7[01]|720))/],
]

let carregando

// Carrega o SDK uma vez, por <script> do nosso domínio com `integrity` (a política de conteúdo da página só libera o próprio domínio).
function carregarSdk(config) {
  if (window.PagSeguro?.encryptCard) return Promise.resolve(window.PagSeguro)
  carregando ??= new Promise((resolver, recusar) => {
    const script = document.createElement("script")
    script.src = config.sdk_url
    script.integrity = config.sdk_integrity
    script.crossOrigin = "anonymous"
    script.onload = () => (window.PagSeguro?.encryptCard ? resolver(window.PagSeguro) : recusar({ reason: "script_blocked" }))
    script.onerror = () => recusar({ reason: "script_blocked" })
    document.head.append(script)
  })
  return carregando
}

export async function brand(_library, _config, number) {
  const found = BRANDS.find(([, pattern]) => pattern.test(number))
  return found ? found[0] : null
}

export async function tokenize(_library, config, card) {
  if (!(await brand(null, config, card.number))) throw { reason: "brand_unsupported" }
  if (!config.public_key) throw { reason: "connection_error" }

  const PagSeguro = await carregarSdk(config)
  const result = PagSeguro.encryptCard({
    publicKey: config.public_key,
    holder: card.holderName,
    number: card.number,
    expMonth: card.expirationMonth,
    expYear: card.expirationYear,
    securityCode: card.cvv,
  })
  if (result.hasErrors || !result.encryptedCard) throw { reason: "form_error" }
  return result.encryptedCard
}
