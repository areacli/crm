// Módulo do navegador do fornecedor falso (12, parte C): não há biblioteca nem domínio externo; o "token" é montado aqui, sem rede, para a demonstração e
// os testes. O último dígito do número escolhe o resultado: 1 dados inválidos, 2 recusa por segurança, 3 recusa que pode repetir; o resto aprova.
const REFUSALS = { 1: "dados-invalidos", 2: "recusado", 3: "tente-depois" }

export async function brand(_library, _config, number) {
  return number.startsWith("4") ? "visa" : "mastercard"
}

export async function tokenize(_library, _config, card) {
  if (card.number.length < 13) throw { reason: "form_error" }
  return REFUSALS[card.number.slice(-1)] ?? `tok-${crypto.randomUUID()}`
}
