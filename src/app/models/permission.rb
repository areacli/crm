# As 17 permissões do sistema (permissoes.md). Cada uma vale por credor e é dada por perfil; o número é o da especificação.
module Permission
  ALL = %w[
    view_portfolio upload_imports confirm_imports change_settings upload_payments confirm_payments record_contact_attempts
    void_others_contact_attempts manage_contact_results manage_users manage_profiles edit_customer_registry
    handle_data_subject_rights change_financial_policies cancel_payment_promises negotiate_agreements administer_agreements
  ].freeze

  # O perfil Operador padrão (MT-21): consultar a carteira e registrar acionamentos.
  OPERATOR = %w[view_portfolio record_contact_attempts].freeze

  def self.number(key) = ALL.index(key.to_s) + 1
  def self.label(key) = I18n.t("permissions.#{key}")
  def self.known?(key) = ALL.include?(key.to_s)
end
