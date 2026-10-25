# As 16 permissões do sistema (permissoes.md). Cada uma vale por credor e é dada por perfil; o número é o da especificação. A permissão 8
# (anular acionamentos de outros) foi retirada com a anulação (04, revisão 5); as demais mantêm o número.
module Permission
  ALL = %w[
    view_portfolio upload_imports confirm_imports change_settings upload_payments confirm_payments record_contact_attempts
    manage_contact_results manage_users manage_profiles edit_customer_registry
    handle_data_subject_rights change_financial_policies cancel_payment_promises negotiate_agreements administer_agreements
  ].freeze

  # O perfil Operador padrão (MT-21): consultar a carteira, registrar acionamentos, editar o cadastro do cliente (06, R113) e negociar acordos (11, R245).
  OPERATOR = %w[view_portfolio record_contact_attempts edit_customer_registry negotiate_agreements].freeze

  RETIRED_NUMBER = 8

  def self.number(key)
    position = ALL.index(key.to_s) + 1
    position >= RETIRED_NUMBER ? position + 1 : position
  end
  def self.label(key) = I18n.t("permissions.#{key}")
  def self.known?(key) = ALL.include?(key.to_s)
end
