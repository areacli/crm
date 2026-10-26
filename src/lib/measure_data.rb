# Massa de dados das medições V4 (`lib/tasks/measure.rake`). Carga de teste não precisa de auditoria por registro: aqui as linhas entram por `insert_all!`
# dos modelos de domínio (decisão 0021, parte 2), em fatias, e a limpeza usa `delete_all` de Active Record. Quando a medição é do fluxo (importação,
# baixa, estorno, tarefas diárias), ela roda pelos mesmos serviços do produto, que gravam pelo ORM com a auditoria de sempre.
module MeasureData
  SLICE = 5_000

  module_function

  # Modelo anônimo de uma tabela sem modelo próprio (limpeza de dados de medição).
  def table(name) = Class.new(ActiveRecord::Base) { self.table_name = name; def self.name = "MeasureData::Table" }

  # Apaga as linhas do credor nas tabelas dadas (as que têm `tenant_id`).
  def clear(tenant_id, *tables) = tables.flatten.each { |name| table(name).where(tenant_id: tenant_id).delete_all }

  # Estatísticas depois de uma carga em massa, como a confirmação faz (sem elas o primeiro plano de consulta é ruim).
  def analyze(*tables)
    connection = ActiveRecord::Base.connection
    (connection.tables & tables.flatten.map(&:to_s)).each { |name| connection.execute("analyze #{connection.quote_table_name(name)}") }
  end

  def insert(model, rows, slice: SLICE) = rows.each_slice(slice) { |part| model.insert_all!(part.to_a, returning: false) }

  # Um cliente por contrato (código `CT-<i>`), `bills_per` títulos por contrato, para os índices `from...from + count`. `document`: (i) => documento; `bill`: (i, n) =>
  # atributos do título (sempre as mesmas chaves); `contract_age`: (i) => dias de idade do contrato. Devolve os ids dos clientes, na ordem.
  def portfolio(tenant_id, count, bills_per: 1, from: 1, document: ->(i) { FakeData.cpf(i) }, contract_age: nil, bill:)
    ids = []
    (from...from + count).each_slice(SLICE) do |slice|
      customers = Customer.insert_all!(slice.map { |i| { tenant_id: tenant_id, document: document.call(i), name: "Cliente #{i}" } }, returning: %w[id]).rows.flatten
      ids.concat(customers)
      contracts = Contract.insert_all!(slice.map do |i|
        { tenant_id: tenant_id, code: "CT-#{i}" }.merge(contract_age ? { created_at: Time.current - contract_age.call(i).days } : {})
      end, returning: %w[id code]).rows.to_h { |id, code| [ code, id ] }
      ContractCustomer.insert_all!(slice.zip(customers).map { |i, id| { contract_id: contracts.fetch("CT-#{i}"), customer_id: id, roles: [] } }, returning: false)
      Bill.insert_all!(slice.zip(customers).flat_map do |i, id|
        (1..bills_per).map { |n| { tenant_id: tenant_id, contract_id: contracts.fetch("CT-#{i}"), customer_id: id }.merge(bill.call(i, n)) }
      end, returning: false)
    end
    ids
  end

  # Perfil por amostragem (PERFIL=1): de 4 em 4 ms anota a linha do app e o topo da pilha da thread principal; mostra as que mais aparecem. Sem gema de perfil.
  def profile(label)
    return yield unless ENV["PERFIL"]

    main = Thread.current
    lines = Hash.new(0)
    tops = Hash.new(0)
    sampler = Thread.new do
      loop do
        sleep 0.004
        trace = main.backtrace || next
        app = trace.find { |line| line.include?("/app/app/") || line.include?("/app/lib/") }
        lines[app.sub("/app/", "")] += 1 if app
        tops[trace.first(2).map { |line| line.sub(%r{.*/gems/}, "")[0, 90] }.join(" < ")] += 1
      end
    end
    result = yield
    sampler.kill
    puts "  perfil de #{label}:"
    lines.sort_by { |_, count| -count }.first(10).each { |line, count| puts format("    %5d %s", count, line) }
    tops.sort_by { |_, count| -count }.first(5).each { |line, count| puts format("    %5d topo %s", count, line) }
    result
  end

  # Tira do credor de medição o que a carga e os serviços gravaram sobre carteira, contratos e importações, na ordem das chaves estrangeiras.
  def wipe_portfolio(tenant_id)
    imports = Import.where(tenant_id: tenant_id).select(:id)
    [ PaymentRow, ImportRow, ImportContact, ImportRejection, ImportWarning ].each { |model| model.where(import_id: imports).delete_all }
    ContractCustomer.where(customer_id: Customer.where(tenant_id: tenant_id).select(:id)).delete_all
    ContractSegment.where(contract_id: Contract.where(tenant_id: tenant_id).select(:id)).delete_all
    Bill.where(tenant_id: tenant_id).delete_all
    Customer.where(tenant_id: tenant_id).delete_all
    Contract.where(tenant_id: tenant_id).delete_all
    ChargeRuleVersion.where(segment_id: Segment.where(tenant_id: tenant_id).select(:id)).delete_all
    Import.where(tenant_id: tenant_id).destroy_all
  end
end
