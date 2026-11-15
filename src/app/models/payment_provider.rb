# Fornecedor de um pagamento (03, revisão 12, R48): quem deu o identificador, o banco, a adquirente ou o fornecedor de pagamento da integração.
# Entra na identidade do pagamento pela chave, lida sem maiúsculas, acentos, espaços, pontos, hífens e sublinhados ("Mercado Pago" e
# "mercadopago" são o mesmo); a chave de um fornecedor com integração é o nome dele no registro (`bradesco`, `pagbank`...), então a planilha
# que escreve "Bradesco" casa com os pagamentos que chegaram pelos instrumentos do Bradesco.
module PaymentProvider
  # O fornecedor do que nasce no próprio CRM (o uso de crédito do contrato).
  CRM = "crm".freeze
  CRM_NAME = "CRM".freeze

  module_function

  def key(raw) = FoldedText.fold(raw).gsub(/[\s._-]+/, "")

  # A conta no fornecedor (agência e conta, convênio, id da conta) entra na identidade lida do mesmo jeito: "2847-1" e "2847 1" são a mesma.
  def account_key(raw) = key(raw)

  # O nome para a tela: o do fornecedor com integração, senão o que foi escrito.
  def label(key, written = nil)
    return CRM_NAME if key == CRM
    return I18n.t("payments.providers.#{key}.name") if Payments::Providers.names.include?(key.to_s)

    written.presence || key.to_s
  end
end
