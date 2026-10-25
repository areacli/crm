# Divergência de valor (R93): o credor mudou o valor de um título que já tinha pagamento aplicado. Nasce aberta na confirmação da carga e é
# tratada pelo financeiro, com nota (R99). O efeito e os números são os da hora da carga; nada aqui é recalculado depois.
class ValueDiscrepancy < ApplicationRecord
  include TenantScoped

  # Efeito aplicado ao título: passa a pago, volta como pago (R97), saldo sobe ou cai, mantido ("manter e registrar") ou só registro (título pago).
  enum :effect, { becomes_paid: "becomes_paid", returns_paid: "returns_paid", balance_up: "balance_up", balance_down: "balance_down", kept: "kept",
                  record_only: "record_only" }, prefix: true, validate: true
  enum :policy, { follow: "follow", keep: "keep" }, prefix: true, validate: true
  enum :status, { open: "open", handled: "handled" }, validate: true
  enum :choice, { keep: "keep", apply: "apply" }, prefix: true, validate: { allow_nil: true }

  belongs_to :bill
  belongs_to :import, optional: true
  belongs_to :handled_by, class_name: "User", optional: true

  scope :recent, -> { order(id: :desc) }

  # "Aplicar o valor informado" só existe onde a política "manter" deixou o valor e o título ainda aceita a mudança (R99).
  def applicable? = open? && effect_kept? && !bill.paid?

  # O valor do título mudou depois desta divergência (outra aplicada): ela ainda pode ser mantida, mas não aplicada.
  def stale? = bill.amount_cents != previous_cents
end
