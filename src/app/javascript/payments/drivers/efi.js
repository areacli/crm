// Módulo do navegador do adaptador Efí (12, parte C): usa a biblioteca `payment-token-efi` (fixada em vendor/javascript, versão ESM) para transformar o
// cartão em `payment_token` direto com a Efí. O que sai daqui para o servidor é só o token. Documentação: dev.efipay.com.br/docs/api-cobrancas/cartao.
const BRANDS = ["visa", "mastercard", "amex", "elo", "hipercard"]

const credit = (library) => library.default.CreditCard

export async function brand(library, _config, number) {
  const found = await credit(library).setCardNumber(number).verifyCardBrand()
  return BRANDS.includes(found) ? found : null
}

export async function tokenize(library, config, card) {
  try {
    const found = await brand(library, config, card.number)
    if (!found) throw { reason: "brand_unsupported" }

    const result = await credit(library)
      .setAccount(config.payee_code)
      .setEnvironment(config.environment)
      .setCreditCardData({ brand: found, number: card.number, cvv: card.cvv, expirationMonth: card.expirationMonth, expirationYear: card.expirationYear, holderName: card.holderName, reuse: false })
      .getPaymentToken()
    return result.payment_token
  } catch (erro) {
    if (erro?.reason) throw erro
    throw { reason: erro?.code === 404 || erro?.error === "request_error" ? "connection_error" : "form_error" }
  }
}
