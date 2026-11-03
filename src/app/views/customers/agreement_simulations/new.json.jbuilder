# Formulário da simulação de acordo na SPA (11, R211 a R218; decisão 0025): os títulos em cobrança com o que impede cada um, os componentes de
# desconto mostrados, a oferta de crédito do contrato e se há proposta vigente que pode ser substituída.
json.cliente @customer.name
json.credor @customer.tenant.name
json.titulos @bills do |bill|
  holder = @held[bill.id]
  why = @ineligible&.dig(bill.id)
  json.id bill.id.to_s
  json.numero bill.number
  json.contrato bill.contract.label
  json.vencimento date_br(bill.due_date)
  json.saldo money(bill.balance_cents)
  json.bloqueado((holder && !holder.proposal?) || why.present?)
  json.selo(why ? selo("Não entra", :warning) : holder ? selo(holder.proposal? ? "Em proposta" : "Em acordo", :warning) : bill.due_date < Date.current ? selo("Vencido", :danger) : selo("A vencer", :info))
  detalhe = []
  detalhe << (bill.kind_break? ? "Título da quebra." : (bill.kind_reversal? ? "Título de estorno." : "Título de acordo #{bill.agreement.number}.")) unless bill.kind_common?
  if why then detalhe << t("agreements.eligibility.#{why}", number: bill.number)
  elsif holder then detalhe << "#{holder.proposal? ? "Em proposta" : "Em acordo"} #{holder.number}."
  end
  json.detalhe detalhe.join(" ").presence
end
json.pode_substituir @held.values.any?(&:proposal?)
shown = Agreements::Caps::COMPONENTS.reverse.reject { |component| Agreements::INHERITED.include?(component) && @bills.none? { |bill| bill.kind_agreement? || bill.kind_break? } }
json.componentes(shown.map { |component| { id: component, nome: "Desconto em #{component_name(component).downcase} (%)" } })
offers = Agreements::CreditUse.available_by_contract(@customer.tenant.setting, @bills)
json.credito(offers.any? ? "Disponível: #{offers.map { |contract, cents| "#{contract.label}, #{money(cents)}" }.join("; ")}. Entra como #{Agreements::Policies.value(@customer.tenant.setting, "credit_entry") == "rebate" ? "abatimento do valor do acordo" : "pagamento da entrada"}." : nil)
