# Contato registrado de um cliente: telefone, e-mail ou endereço, com origem, situação e a marca "mantido pelo credor" (R108). Único por
# cliente + tipo + forma normalizada (R125): é o banco, e não o código, que garante que "igual" é uma regra só.
class CustomerContact < ApplicationRecord
  include TenantScoped
  include OperationOrigin

  belongs_to :customer
  belongs_to :updated_by, class_name: "User", optional: true

  enum :kind, { phone: "phone", email: "email", address: "address" }, validate: true
  # `valid` e `invalid` colidiriam com `valid?` e `invalid?` do Active Model: por isso o prefixo.
  enum :status, { valid: "valid", invalid: "invalid", do_not_disturb: "do_not_disturb" }, prefix: :status, validate: true
  # De onde o contato veio na primeira vez; não muda (R108).
  enum :origin, { load: "load", screen: "screen", contact_attempt: "contact_attempt" }, prefix: :from, validate: true

  KIND_ORDER = { "phone" => 0, "email" => 1, "address" => 2 }.freeze
  STATUS_ORDER = { "valid" => 0, "do_not_disturb" => 1, "invalid" => 2 }.freeze
  # Canal do acionamento → tipo de contato oferecido (R120).
  CHANNEL_KINDS = { "phone" => "phone", "whatsapp" => "phone", "sms" => "phone", "email" => "email", "letter" => "address", "in_person" => "address" }.freeze

  validates :value, :key, presence: true

  def no_area_code? = phone? && key.length <= 9

  # Todos, para a aba Contatos: válidos antes, depois não perturbe e inválidos; dentro da situação, por tipo.
  def self.listed(contacts) = contacts.sort_by { |c| [ STATUS_ORDER.fetch(c.status), KIND_ORDER.fetch(c.kind), c.id ] }
end
