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

  def make_segment(tenant, name, **criteria)
    position = Segment.where(tenant: tenant, catch_all: false).maximum(:position).to_i + 1
    Segment.create!(tenant: tenant, name: name, position: position, **criteria)
  end

  def recalc(tenant) = Segments::Recalculation.new(tenant).apply

  def segment_of(contract) = contract.reload.segment&.name
end
