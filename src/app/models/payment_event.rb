# Aviso de um fornecedor de pagamento (12, parte D, R281 e R282): um registro por aviso, único por conta e identificador do evento (o repetido é
# ignorado, ou reabre o aviso quando o fornecedor reaproveita o identificador, como o token da Efí). Guarda só o mínimo (identificadores, estados,
# valor e horário; nunca dado do pagador nem de cartão). Estados: `received` (a processar), `applied` (mudou algo), `ignored` (nada a fazer),
# `review` (o fato foi aceito, mas o efeito no CRM espera alguém: por exemplo, instrumento sem título ligado) e `failed` (esgotou as tentativas; a
# reprocessagem tenta de novo).
class PaymentEvent < ApplicationRecord
  include TenantScoped

  belongs_to :account, class_name: "PaymentAccount", inverse_of: :events
  belongs_to :instrument, class_name: "PaymentInstrument", optional: true

  enum :kind, { paid: "paid", refunded: "refunded", canceled: "canceled", expired: "expired", check: "check", other: "other" }, prefix: true, validate: true
  enum :state, { received: "received", applied: "applied", ignored: "ignored", review: "review", failed: "failed" }, prefix: true, validate: true

  validates :event_id, presence: true, length: { maximum: 200 }
  validate :account_of_same_tenant

  # Tentativas antes de desistir (o job para de repetir e o aviso fica `failed`; a reprocessagem diária ainda o retoma até este limite de rodadas).
  MAX_RESTARTS = 10

  scope :pending, -> { where(state: %w[received failed]) }

  # Guarda um aviso normalizado da conta. Devolve [evento, novo?]. Repetido: ignora, ou reabre quando o aviso diz `reprocess` e o anterior já terminou.
  def self.record(account, notification)
    event = new(tenant_id: account.tenant_id, account: account, event_id: notification.event_id, kind: notification.kind, external_id: notification.external_id,
                amount_cents: notification.amount_cents, occurred_at: notification.occurred_at, previous_status: notification.previous_status&.first(40),
                current_status: notification.current_status&.first(40), summary: summary_of(notification))
    event.save!
    [ event, true ]
  rescue ActiveRecord::RecordNotUnique
    existing = find_by!(account_id: account.id, event_id: notification.event_id)
    reopened = notification.reprocess && existing.state.in?(%w[applied ignored])
    existing.update!(state: "received", outcome: nil, attempts: 0, processed_at: nil) if reopened
    [ existing, reopened ]
  end

  # O corpo mínimo: o que identifica o aviso, nada do pagador.
  def self.summary_of(notification)
    { "token" => notification.token, "end_to_end_id" => notification.end_to_end_id, "custom_id" => notification.custom_id }.compact
  end

  # O aviso de volta no formato do adaptador (para o job completar e consultar).
  def to_notification
    Payments::Providers::Notification.new(event_id: event_id, kind: kind, external_id: external_id, amount_cents: amount_cents, occurred_at: occurred_at,
                                          token: summary["token"], end_to_end_id: summary["end_to_end_id"], custom_id: summary["custom_id"],
                                          previous_status: previous_status, current_status: current_status)
  end

  def finish!(state, outcome, instrument: nil)
    update!(state: state, outcome: outcome.to_s.first(300), processed_at: Time.current, instrument: instrument || self.instrument)
  end

  private
    def account_of_same_tenant
      errors.add(:account, :other_tenant) if account && account.tenant_id != tenant_id
    end
end
