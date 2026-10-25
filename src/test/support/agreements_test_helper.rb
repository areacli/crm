# Acordos para os testes (11): a Maria da especificação (NF-1 e NF-2 no segmento "Demais" com as variáveis do exemplo), Price a 1,5% ao mês e a simulação
# montada como o formulário faz. A data da montagem é 30/10/2026, sexta-feira, e o credor tem CNPJ e razão social (o termo só existe com eles).
module AgreementsTestHelper
  AGREEMENT_DAY = Date.new(2026, 10, 30)

  # Variáveis do segmento "Varejo PF recente" do exemplo (R207): multa e juros até 100%, principal e correção 0% (à vista, também 30% na correção), até 12 parcelas,
  # parcela mínima de R$ 100,00, entrada mínima de 10% em até 10 dias, validade de 5 dias, tolerância de 3 dias e quebra com 30.
  EXAMPLE_VARIABLES = {
    agreement_caps: { "installment" => { "fine" => 100, "interest" => 100, "fees" => 50 }, "cash" => { "fine" => 100, "interest" => 100, "fees" => 50, "correction" => 30 } },
    agreement_max_installments: 12, agreement_min_installment_cents: 10_000, agreement_min_down_payment_pct: 10, agreement_down_payment_days: 10,
    agreement_validity_days: 5, agreement_tolerance_days: 3, agreement_break_days: 30
  }.freeze

  # Maria com NF-1 e NF-2; devolve [cliente, NF-1, NF-2]. O limite do Operador é a metade das variáveis (DA4), criado como o gatilho faria.
  def agreement_scenario(tenant = tenants(:alfa), price: true)
    tenant.update!(cnpj: "11222333000181", legal_name: "Escola Alfa Ltda") if tenant.cnpj.blank?
    customer, nf1, nf2 = promise_scenario(tenant)
    segment = Segment.catch_all_of(tenant)
    segment.update!(**EXAMPLE_VARIABLES)
    tenant.setting.update!(installment_rate_pct: 1.5, installment_method: "price") if price
    rebuild_agreement_limits(tenant)
    [ customer, nf1, nf2 ]
  end

  # Refaz os limites dos perfis do credor pelo padrão da DA4 (as fixtures não rodam os gatilhos).
  def rebuild_agreement_limits(tenant)
    AgreementLimit.where(segment_id: tenant.segments.select(:id)).delete_all
    tenant.segments.find_each { |segment| AgreementLimit.create_for_segment(segment) }
  end

  # A entrada da simulação como o formulário monta (descontos em centésimos de ponto; entrada em centavos).
  def agreement_input(bills, mode: "installments", discounts: { "fine" => 5_000, "interest" => 5_000 }, down: 34_366, down_on: Date.new(2026, 11, 5), installments: 4, day: 5, replace: false, credit: 0)
    Agreements::Simulation::Input.new(bill_ids: bills.map(&:id), mode: mode, discounts_bp: Agreements::Caps::COMPONENTS.to_h { |component| [ component, discounts.fetch(component, 0) ] },
                                      down_payment_cents: down, down_payment_on: down_on, installments: installments, day: day, replace: replace, credit_cents: credit)
  end

  def simulate_agreement(customer, bills, user: users(:carlos), **options)
    Agreements::Simulation.new(user: user, customer: customer, input: agreement_input(bills, **options)).call
  end

  def create_proposal(customer, bills, user: users(:carlos), **options)
    Agreements::Proposal.new(user, customer).create(agreement_input(bills, **options))
  end

  def refuse_agreement(&block) = assert_raises(Agreements::Refused, &block).message

  # Registra o aceite como o operador faria (apresentação 14h50, aceite 15h10, registro 15h30 do dia da montagem).
  def accept_proposal(agreement, customer, actor: users(:carlos), day: AGREEMENT_DAY)
    at = ->(hour, minute) { day.in_time_zone.change(hour: hour, minute: minute) }
    input = Agreements::Acceptance::Input.new("whatsapp", at.call(14, 50), "phone", at.call(15, 10), "88213", customer.id)
    Agreements::Acceptance.new(actor).call(agreement, input, now: at.call(15, 30))
  end

  # Proposta aceita da Maria (aguardando efetivação) com o canal de pagamentos pronto; devolve [cliente, NF-1, NF-2, acordo].
  def accepted_agreement(tenant = tenants(:alfa), **options)
    customer, nf1, nf2 = agreement_scenario(tenant)
    make_channel(tenant)
    agreement = create_proposal(customer, [ nf1, nf2 ], **options)
    accept_proposal(agreement, customer)
    [ customer, nf1, nf2, agreement.reload ]
  end

  # Importa e confirma pagamentos na data de hoje (a linha leva a data de pagamento em dd/mm/aaaa).
  def pay_lines(lines, tenant: tenants(:alfa)) = run_payments_import(lines, kind: "payments", tenant: tenant, confirm: true)

  def pay_line(number, date, amount, id: "PIX-#{SecureRandom.hex(3)}", **overrides)
    payment_line({ "identificador" => id, "titulo" => number, "data_pagamento" => date.strftime("%d/%m/%Y"), "valor" => Money.format(amount) }.merge(overrides.transform_keys(&:to_s)))
  end
end
