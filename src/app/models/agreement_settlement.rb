# Cálculo da quitação antecipada de um acordo (11, R230): o saldo para uma data (a amortização que falta, os juros do parcelamento já corridos e a mora, sem os juros
# futuros). Vale até a própria data; o pagamento usa o cálculo de menor data igual ou posterior à data dele; perde a validade quando o acordo recebe pagamento ou
# estorno depois dele.
class AgreementSettlement < ApplicationRecord
  belongs_to :agreement
  belongs_to :user, optional: true

  scope :valid_on, ->(date) { where(expired_at: nil).where(on_date: date..).order(:on_date, :id) }

  # { id do título => { componente => centavos } } do que a quitação cobra de cada título.
  def parts_by_bill = parts.transform_keys(&:to_i)

  # Calcula e grava o saldo do acordo para `on` (R230): só para acordo ativo ou quebrado na forma "parcelas seguem".
  def self.calculate!(agreement, on:, user: nil, today: Date.current)
    titles = agreement.titles.where(status: "active").to_a
    ledgers = Agreements::LedgerLoader.new(agreement.tenant, today: [ on, today ].max).call(titles)
    parts = titles.to_h { |bill| [ bill.id.to_s, ledgers.fetch(bill.id).balance_parts(on).first ] }.reject { |_, items| items.empty? }
    transaction do
      record = create!(agreement: agreement, user: user, on_date: on, amount_cents: parts.values.sum { |items| items.values.sum }, parts: parts, created_at: Time.current)
      AgreementEvent.log!(agreement, "settlement_calculated", user: user, data: { "on" => on.iso8601, "amount_cents" => record.amount_cents })
      record
    end
  end
end
