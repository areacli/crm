# Encargos para os testes (09): índices reais de 2026 gravados (nenhum teste chama o Banco Central), parâmetros do credor e títulos da Maria.
module ChargesTestHelper
  TODAY = Date.new(2026, 10, 21)
  DUE = Date.new(2026, 7, 15)

  def seed_indexes!
    { "ipca" => { [ 2026, 7 ] => "0.07", [ 2026, 8 ] => "-0.32", [ 2026, 9 ] => "0.82" },
      "legal" => { [ 2026, 7 ] => "0.706607", [ 2026, 8 ] => "1.154527", [ 2026, 9 ] => "1.499119", [ 2026, 10 ] => "0.379020" } }.each do |series, values|
      values.each { |(year, month), value| IndexRate.create!(series: series, month: Date.new(year, month, 1), value: BigDecimal(value), fetched_at: Time.current) }
    end
  end

  # Regra do "Varejo PF recente" dada como parâmetro do credor: multa 2%, juros de taxa fixa 1% ao mês e IPCA (os segmentos herdam).
  def configure_charges(tenant, fine: 2, interest: 1, index: "ipca", **policies)
    tenant.setting.update!(charge_fine_pct: fine, charge_interest_pct: interest, charge_index: index, **policies)
    demais = Segment.catch_all_of(tenant)
    demais.update!(interest_kind: interest.to_d.positive? ? "fixed" : "none")
    Charges::RuleHistory.record!(tenant, since: Date.new(2026, 1, 1))
  end

  def recalc_values(tenant, today: TODAY) = Charges::Recalculation.new(tenant).apply(today: today)

  def valuation_of(bill) = BillValuation.find_by(bill_id: bill.id)

  def total_of(bill) = valuation_of(bill)&.total_cents
end
