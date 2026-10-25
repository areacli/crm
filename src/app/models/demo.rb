# Modo de demonstração pública (CRM_DEMO=1): a vitrine do blog, não uma funcionalidade do produto. Tudo o que a
# demonstração precisa fica aqui e em `app/models/demo/`; fora do modo ligado, nada disto tem efeito.
module Demo
  WHO = %w[gestor operador].freeze

  module_function

  def enabled? = Rails.configuration.x.demo.enabled
  def domain = Rails.configuration.x.demo.domain
  def customers = Rails.configuration.x.demo.customers
  def reset_at = Rails.configuration.x.demo.reset_at

  def email(who) = "#{who}@#{domain}"
  def password(who) = "demonstracao-#{who}"

  # Os usuários públicos: senhas legíveis, que ninguém pode trocar.
  def public_user?(user) = enabled? && user.present? && WHO.any? { |who| user.email_address == email(who) }
end
