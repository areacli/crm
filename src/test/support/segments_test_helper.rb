# Índices e segmentos para os testes (08): cliente HTTP falso (nenhum teste chama o Banco Central), contratos com vários títulos e clientes,
# e segmentos com critérios.
module SegmentsTestHelper
  CNPJ_A = "11222333000181".freeze
  CNPJ_B = "11444777000161".freeze

  # Substitui o cliente do Banco Central: `answers` mapeia o código da série para a lista [["01/01/2024", "0.42"], ...] ou para uma exceção.
  class FakeClient
    attr_reader :calls

    def initialize(answers = {}) = (@answers = answers; @calls = [])

    def series(code, from:, to:)
      @calls << [ code, from, to ]
      answer = @answers.fetch(code, [])
      raise answer if answer.is_a?(Exception)

      answer.map { |date, value| { "data" => date, "valor" => value } }
    end
  end

  # Cliente que recusa qualquer chamada: o padrão dos testes, para garantir que nada vai à internet.
  class BlockedClient
    def series(*, **) = raise("o teste tentou chamar o Banco Central")
  end

  def self.included(base)
    base.setup { Indexes.client = BlockedClient.new }
    base.teardown { Indexes.client = nil }
  end

  def fake_bank(answers) = (Indexes.client = FakeClient.new(answers))

  def customer_of(tenant, document, name = "Cliente #{document[-4, 4]}")
    Customer.find_or_create_by!(tenant: tenant, document: document) { |customer| customer.name = name }
  end

  # Contrato com títulos; cada título é { due:, cents:, product:, customer: }. `customers` entra com os papéis dados em `roles`.
  def make_contract(tenant, code, bills: [], customers: [], created_ago: 100, roles: {})
    contract = Contract.create!(tenant: tenant, code: code)
    contract.update_columns(created_at: created_ago.days.ago)
    customers = [ customer_of(tenant, FakeData.cpf(code.hash.abs % 900 + 20)) ] if customers.empty?
    customers.each { |customer| ContractCustomer.create!(contract: contract, customer: customer, roles: roles.fetch(customer.id, [])) }
    bills.each_with_index do |bill, index|
      Bill.create!(tenant: tenant, contract: contract, customer: bill[:customer] || customers.first, number: "#{code}-#{index}", due_date: Date.current - bill.fetch(:overdue, 10),
                   amount_cents: bill.fetch(:cents, 100_000), paid_cents: bill.fetch(:paid, 0), product: bill[:product])
    end
    contract
  end

  RANGE_PATHS = { overdue_days: [ "overdue_days" ], balance_cents: [ "balance" ], overdue_percent: [ "overdue_percent" ], age_days: [ "age_days" ],
                  overdue_bills: [ "bills", "overdue" ], customers: [ "customers" ] }.freeze

  # As condições na linguagem (13) a partir dos critérios da 08 que os testes antigos usavam: faixas, tipo, produto e "já quebrou acordo".
  def conditions_from(criteria)
    list = []
    RANGE_PATHS.each do |name, (path, qualifier)|
      low = criteria[:"min_#{name}"]
      high = criteria[:"max_#{name}"]
      next if low.nil? && high.nil?

      node = { "path" => path }
      node.merge!("aggregate" => "count") if %w[bills customers].include?(path)
      node["qualifier"] = qualifier if qualifier
      node.merge!(low && high ? { "op" => "between", "value" => [ low, high ] } : (low ? { "op" => "gte", "value" => low } : { "op" => "lte", "value" => high }))
      list << node
    end
    list << { "path" => "person_type", "op" => "eq", "value" => criteria[:person_type] } if criteria[:person_type]
    list << { "path" => "product", "op" => "in", "value" => Array(criteria[:products]) } if Array(criteria[:products]).any?
    list << { "path" => "broke_agreement", "op" => "is", "negate" => criteria[:broke_agreement] == "no" } if criteria[:broke_agreement]
    list.presence || [ { "path" => "overdue_days", "op" => "gte", "value" => 0 } ]
  end

  CRITERIA_KEYS = (RANGE_PATHS.keys.flat_map { |name| [ :"min_#{name}", :"max_#{name}" ] } + %i[person_type products broke_agreement]).freeze

  # Segmento (filtro) do credor.
  def make_segment(tenant, name, conditions = nil, subject: "contracts", **criteria)
    Segment.create!(tenant: tenant, name: name, subject: subject, expression: { "all" => conditions || conditions_from(criteria) })
  end

  # Item do enquadramento financeiro com um segmento novo, no fim (antes do "Demais"); as chaves que não são critério viram regras do item.
  def make_tier(tenant, name, conditions = nil, **options)
    segment = make_segment(tenant, name, conditions, **options.slice(*CRITERIA_KEYS))
    position = Tier.financial.where(tenant: tenant, catch_all: false).maximum(:position).to_i + 1
    Tier.create!(tenant: tenant, kind: "financial", segment: segment, position: position, **options.except(*CRITERIA_KEYS))
  end

  def recalc(tenant) = Tiers::Recalculation.new(tenant).apply

  def tier_of(contract) = contract.reload.tier&.name
end
