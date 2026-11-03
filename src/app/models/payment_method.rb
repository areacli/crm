# Meio de pagamento (16, MP1a: "meio e método de pagamento são a mesma coisa"): como se paga. Catálogo em código, igual para o pagamento, a
# promessa e a planilha: a chave vai nas colunas `payment_method`, o rótulo vem de `payments.methods`. O que o CRM emite (boleto, Pix e o link
# de cartão de crédito) é um subconjunto (`ISSUABLE`).
module PaymentMethod
  KEYS = %w[pix pix_recurring boleto credit_card debit_card transfer cash other].freeze
  # Para o `enum` dos modelos: chave => valor gravado.
  ENUM = KEYS.to_h { |key| [ key.to_sym, key ] }.freeze

  # Os meios que o CRM emite (16, R377) e o tipo de instrumento de cada um (o cartão é o link de checkout).
  ISSUABLE = { "boleto" => "boleto", "pix" => "pix", "credit_card" => "card" }.freeze

  # Como a planilha escreve cada meio, sem maiúsculas, acentos, espaços, hífens nem sublinhados (R49).
  SHEET_ALIASES = {
    "pix" => "pix", "pixrecorrente" => "pix_recurring", "pixautomatico" => "pix_recurring", "boleto" => "boleto",
    "cartaodecredito" => "credit_card", "cartaocredito" => "credit_card", "cartaododebito" => "debit_card", "cartaodebito" => "debit_card",
    "cartaodedebito" => "debit_card", "transferencia" => "transfer", "dinheiro" => "cash", "outro" => "other"
  }.freeze

  module_function

  def label(key) = I18n.t("payments.methods.#{key}")

  def known?(key) = KEYS.include?(key.to_s)

  # O meio lido da planilha; nil quando fora da lista.
  def from_sheet(raw) = SHEET_ALIASES[FoldedText.fold(raw.to_s).delete(" -_")]

  # O meio de pagamento do pagamento que chega por um instrumento (R375): o link só aceita crédito.
  def for_instrument(kind) = ISSUABLE.key(kind.to_s)

  def options = KEYS.map { |key| [ label(key), key ] }
end
