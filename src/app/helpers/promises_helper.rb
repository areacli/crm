# Apresentação das promessas (10): o selo do estado, a linha do cabeçalho da ficha e os títulos.
module PromisesHelper
  TONES = { "pending" => :warning, "open" => :info, "fulfilled" => :success, "fulfilled_late" => :success, "broken" => :danger,
            "canceled" => :neutral, "refused" => :neutral, "not_approved" => :neutral }.freeze

  def promise_state(promise) = situacao(t("promises.states.#{promise.state}"), tom: TONES.fetch(promise.state))

  # Números dos títulos que ainda contam na promessa.
  def promise_bill_numbers(promise) = promise.promise_bills.reject(&:removed?).map { |row| row.bill.number }.to_sentence
end
