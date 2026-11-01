# Medição das operações com o esquema real (plano técnico da camada 18, etapas 4 e 5): 200 mil contratos, 50 mil distribuídos a uma operação,
# 200 mil acionamentos e 50 mil promessas (um quarto e metade com a origem da operação). Mede o alcance, as telas do usuário de operação com o
# RLS, o filtro de origem da equipe e o custo da trilha. Só fora de produção, num banco descartável.
require_relative "../measure_data"

namespace :crm do
  desc "Mede operações no esquema real: crm:measure_operations_schema[contratos,distribuidos]"
  task :measure_operations_schema, %i[contracts distributed] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info
    count = (args[:contracts].presence || 200_000).to_i
    distributed = (args[:distributed].presence || 50_000).to_i
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      puts format("%-76s %8.3f s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      result
    end

    tenant = Tenant.provision!("Medição de operações #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    customer_ids = measure.call("massa: #{count} contratos, #{count * 3} títulos") do
      MeasureData.portfolio(t, count, bills_per: 3, bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - ((i * 37 + n * 11) % 500) + 60,
                                                                         amount_cents: 5000 + (i * 7919 + n * 131) % 250_000 } })
    end
    contracts = Contract.where(tenant_id: t).order(:id).pluck(:id)
    operation = Operation.create!(cnpj: "11222333000262", legal_name: "Medição Cobranças Ltda", short_name: "Medição")
    Accreditation.create!(tenant: tenant, operation: operation)
    profile = tenant.profiles.create!(name: "Operador de operação", permissions: Permission::OPERATOR, available_to_operations: true)
    user = User.create!(name: "Pessoa da operação", email_address: "medicao-#{t}@operacao.exemplo.com.br", password: "lua-cheia-sobre-o-rio-82")
    OperationMember.create!(operation: operation, user: user, manager: true)
    Membership.create!(user: user, tenant: tenant, profile: profile, operation: operation)
    team = User.create!(name: "Equipe", email_address: "medicao-#{t}@equipe.exemplo.com.br", password: "lua-cheia-sobre-o-rio-82")
    Membership.create!(user: team, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))

    measure.call("#{distributed} distribuições (insert_all)") do
      MeasureData.insert(Distribution, contracts.first(distributed).each_with_index.map do |contract_id, i|
        { tenant_id: t, operation_id: operation.id, contract_id: contract_id, exposure: i % 3 == 0 ? "all" : "overdue", starts_on: Date.current - 10, source: "manual",
          created_at: Time.current, updated_at: Time.current }
      end)
    end
    measure.call("alcance (Operations::ReachBuilder#rebuild)") { Operations::ReachBuilder.new(tenant).rebuild }

    result = ContactResult.where(tenant_id: t).first
    measure.call("200 mil acionamentos (um quarto da operação)") do
      MeasureData.insert(ContactAttempt, (0...200_000).map do |i|
        at = Time.current - (i % 60).days - (i % 600).minutes
        { tenant_id: t, customer_id: customer_ids[i % customer_ids.size], user_id: (i % 4).zero? ? user.id : team.id, operation_id: ((i % 4).zero? ? operation.id : nil),
          result_id: result.id, result_kind: result.kind, channel: "phone", contacted_at: at, created_at: at, updated_at: at }
      end)
    end
    attempt_ids = ContactAttempt.where(tenant_id: t).order(:id).limit(50_000).pluck(:id, :customer_id)
    contract_of = ContractCustomer.where(customer_id: attempt_ids.map(&:last)).pluck(:customer_id, :contract_id).to_h
    measure.call("50 mil promessas (metade da operação)") do
      MeasureData.insert(PaymentPromise, attempt_ids.each_with_index.map do |(attempt_id, customer_id), i|
        { tenant_id: t, customer_id: customer_id, contract_id: contract_of.fetch(customer_id), contact_attempt_id: attempt_id, operation_id: (i.even? ? operation.id : nil),
          state: %w[open fulfilled broken][i % 3], payment_method: "pix", promised_on: Date.current + (i % 20), contacted_on: Date.current - (i % 30),
          total_cents: 10_000 + i, created_at: Time.current - (i % 30).days, updated_at: Time.current }
      end)
    end
    MeasureData.analyze(%w[customers contracts contract_customers bills distributions operation_contracts operation_customers contact_attempts payment_promises])

    puts "\nUsuário de operação (RLS):"
    Operations::Context.for_user(user) do
      query = Portfolio::Query.new(user)
      measure.call("lista de clientes, página de 20 por atraso") { Pagination.new(query.customers, page: 1, per_page: 20).records.to_a.size }
      measure.call("busca por nome") { Pagination.new(query.customers(search: "Cliente 1234"), page: 1, per_page: 20).records.to_a.size }
      measure.call("resumo da carteira") { Portfolio::Summary.new(user).totals }
      measure.call("ficha: um cliente distribuído") { Customer.find(customer_ids.first) }
      measure.call("acionamentos: últimos 7 dias, 20 por data") { ContactAttempt.where(contacted_at: 7.days.ago..).order(contacted_at: :desc).limit(20).to_a.size }
    end

    puts "\nEquipe do credor, filtro de origem (R318):"
    Operations::Context.for_user(team) do
      measure.call("acionamentos da operação, 7 dias, página de 20") { ContactAttempt.where(tenant_id: t, operation_id: operation.id, contacted_at: 7.days.ago..).order(contacted_at: :desc).limit(20).to_a.size }
      measure.call("acionamentos da equipe, 7 dias, contagem") { ContactAttempt.where(tenant_id: t, operation_id: nil, contacted_at: 7.days.ago..).count }
      measure.call("promessas da operação, página de 20") { PaymentPromise.where(tenant_id: t, operation_id: operation.id).order(created_at: :desc).limit(20).to_a.size }
      measure.call("promessas da operação, contagem") { PaymentPromise.where(tenant_id: t, operation_id: operation.id).count }
    end

    puts "\nTrilha (R320):"
    Operations::Context.for_user(user) do
      opened = Customer.where(id: customer_ids.first(1_000)).to_a
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      opened.each { |customer| Operations::Trail.record("record_opened", user: user, customer: customer) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format("%-76s %8.3f s (%.2f ms cada)", "1.000 fichas abertas gravadas na trilha", elapsed, elapsed)
    end
  end
end
