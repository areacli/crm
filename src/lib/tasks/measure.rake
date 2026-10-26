# Medições com volume (V4) e planilhas fictícias. Nada disto roda em produção.
# A massa de dados entra por `insert_all!` dos modelos (`lib/measure_data.rb`); o que se mede do fluxo roda pelos serviços do produto (ORM e auditoria).
require_relative "../measure_data"

namespace :crm do
  desc "Gera uma planilha de carteira fictícia: crm:fake_csv[linhas,arquivo,títulos_por_cliente,deslocamento]"
  task :fake_csv, %i[lines path per_customer offset] => :environment do |_task, args|
    lines = args.fetch(:lines).to_i
    per = [ args[:per_customer].to_i, 1 ].max.then { |value| args[:per_customer].blank? ? 2 : value }
    offset = args[:offset].to_i
    today = Date.current
    File.open(args.fetch(:path), "wb") do |file|
      file.write "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n"
      lines.times do |i|
        customer = offset + i / per
        days = 1 + ((customer * 37 + i * 11) % 500)
        cents = 5000 + ((i * 7919) % 250_000)
        file.write [ FakeData.cpf(customer), FakeData.name(customer), "(11) 9#{(customer % 100_000_000).to_s.rjust(8, '0')}",
                     "cliente#{customer}@exemplo.com.br", "CT-#{customer.to_s.rjust(7, '0')}", "NF-#{customer}/#{i % per + 1}",
                     (today - (days - 20)).strftime("%d/%m/%Y"), Money.format(cents), "Mensalidade" ].join(";") + "\n"
      end
    end
    puts "#{lines} linhas gravadas em #{args[:path]}"
  end

  desc "V4-lote: importa uma carteira fictícia e mede vazão (linhas/s) e tempo total da conferência e da confirmação, e as telas durante o lote: crm:measure_import[linhas,títulos_por_cliente]"
  task :measure_import, %i[lines per_customer] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão
    lines = (args[:lines].presence || 10_000).to_i
    per = (args[:per_customer].presence || 2).to_i
    tenant = Tenant.provision!("Medição #{Time.current.strftime('%H%M%S')}")
    user = User.create!(name: "Medição", email_address: "medicao#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    path = Rails.root.join("tmp", "medicao-#{tenant.id}.csv").to_s

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      puts format("%-45s %8.2f s   (pico de memória %d MB)", label, elapsed, peak)
      result
    end

    Rake::Task["crm:fake_csv"].invoke(lines.to_s, path, per.to_s)
    service = Portfolio::ImportService.new
    ActiveJob::Base.queue_adapter = :test
    import = measure.call("envio e gravação do arquivo") { service.start(tenant: tenant, user: user, file: path, mode: :incremental) }
    rate = ->(label, seconds) { puts format("  vazão %-12s %8.1f linhas/s (mínimo do requisito: 50)", label, lines / seconds) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    measure.call("conferência de #{lines} linhas") { Portfolio::ImportChecker.new.run(import) }
    rate.call("conferência", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    import.reload
    puts "  resumo: #{import.summary.slice('valid', 'rejected', 'customers').to_json}"

    # As telas durante o lote: uma thread consulta a lista e o resumo de outro credor-usuário enquanto a confirmação grava.
    probes = []
    watcher = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        until Thread.current[:stop]
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Portfolio::Query.new(user).customers.limit(20).to_a
          Portfolio::Summary.new(user).totals
          probes << Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
          sleep 2
        end
      end
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    measure.call("confirmação de #{lines} linhas") { Portfolio::ImportConfirmer.new.run(import) }
    rate.call("confirmação", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    watcher[:stop] = true
    watcher.join
    puts "  situação: #{import.reload.status}"
    puts format("  telas durante a confirmação (lista + resumo): %d consultas, mediana %.2f s, pior %.2f s", probes.size, probes.sort[probes.size / 2].to_f, probes.max.to_f) if probes.any?

    query = Portfolio::Query.new(user)
    measure.call("lista de clientes (primeira página)") { query.customers.limit(20).to_a }
    measure.call("lista de clientes (contagem total)") { query.customers.except(:select, :order).count }
    measure.call("lista de clientes (busca por nome)") { query.customers(search: "silva").limit(20).to_a }
    measure.call("resumo da carteira") { Portfolio::Summary.new(user).totals }

    File.delete(path) if File.exist?(path)
    ImportRow.where(import_id: import.id).delete_all
    [ BillValueVersion, ReportedSurcharge, ValueDiscrepancy, Change ].each { |model| model.where(tenant_id: tenant.id).delete_all }
    ContractCustomer.where(customer_id: Customer.where(tenant_id: tenant.id)).delete_all
    Bill.where(tenant_id: tenant.id).delete_all
    Customer.where(tenant_id: tenant.id).delete_all
    Contract.where(tenant_id: tenant.id).delete_all
    Import.where(tenant_id: tenant.id).destroy_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 de pagamentos: carteira fictícia de uma linha por cliente, importa pagamentos e estornos e mede: crm:measure_payments[pagamentos,estornos]"
  task :measure_payments, %i[payments reversals] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:payments].presence || 10_000).to_i
    reversal_count = (args[:reversals].presence || count / 10).to_i
    tenant = Tenant.provision!("Medição de pagamentos #{Time.current.strftime('%H%M%S')}")
    user = User.create!(name: "Medição", email_address: "medicao#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "341-1234-56789", description: "Conta de medição")
    ActiveJob::Base.queue_adapter = :test

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      puts format("%-45s %8.2f s   (pico de memória %d MB)", label, elapsed, peak)
      result
    end

    # V4-lote: tempo, vazão (linhas/s; mínimo do requisito: 50) e as telas durante o lote (lista e resumo a cada 2 s, em outra conexão).
    batch = lambda do |label, rows, &work|
      probes = []
      watcher = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          until Thread.current[:stop]
            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            Portfolio::Query.new(user).customers.limit(20).to_a
            Portfolio::Summary.new(user).totals
            probes << Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
            sleep 2
          end
        end
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      measure.call(label, &work)
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      watcher[:stop] = true
      watcher.join
      puts format("  vazão %.1f linhas/s (mínimo do requisito: 50); total %.0f s", rows / seconds, seconds)
      puts format("  telas durante o lote (lista + resumo): %d consultas, mediana %.2f s, pior %.2f s", probes.size, probes.sort[probes.size / 2].to_f, probes.max.to_f) if probes.any?
    end

    # Carteira: um cliente, um contrato e um título por pagamento previsto (valor conhecido, para os perfis abaixo).
    measure.call("carteira de #{count} títulos (insert_all! dos modelos)") do
      MeasureData.portfolio(tenant.id, count, from: 0, bill: ->(index, _n) { { number: "NF-#{index}", due_date: Date.current - 30, amount_cents: 10_000 + ((index * 7919) % 200_000) } })
    end
    MeasureData.analyze("bills", "customers")

    methods = %w[pix boleto cartão\ de\ crédito transferência]
    payments_path = Rails.root.join("tmp", "pagamentos-#{tenant.id}.csv").to_s
    File.open(payments_path, "wb") do |file|
      file.write "canal;identificador;documento;titulo;data_pagamento;valor;meio\n"
      count.times do |index|
        amount = 10_000 + ((index * 7919) % 200_000)
        # 60% quitam, 20% parciais, 10% a mais, 10% de título inexistente.
        value, number = case index % 10
        when 0..5 then [ amount, "NF-#{index}" ]
        when 6, 7 then [ amount / 2, "NF-#{index}" ]
        when 8 then [ amount + 5_000, "NF-#{index}" ]
        else [ amount, "NF-X#{index}" ]
        end
        file.write [ channel.code, "ID-#{index}", FakeData.cpf(index), number, (Date.current - 1).strftime("%d/%m/%Y"), Money.format(value), methods[index % 4] ].join(";") + "\n"
      end
    end
    service = Portfolio::ImportService.new
    import = measure.call("envio do arquivo de #{count} pagamentos") { service.start(tenant: tenant, user: user, file: payments_path, mode: :incremental, kind: "payments") }
    batch.call("conferência de #{count} pagamentos", count) { import.checker.run(import) }
    puts "  resumo: #{import.reload.summary.slice('valid', 'rejected').to_json} efeito: #{import.summary['effect'].to_json}"
    batch.call("confirmação de #{count} pagamentos", count) { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}"
    measure.call("resumo da carteira com recebimentos") { Portfolio::Summary.new(user).totals }

    # Estornos de pagamentos que quitaram (índice múltiplo de 10), 30% do valor de cada um.
    reversals_path = Rails.root.join("tmp", "estornos-#{tenant.id}.csv").to_s
    File.open(reversals_path, "wb") do |file|
      file.write "canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo\n"
      reversal_count.times do |position|
        index = position * 10
        amount = 10_000 + ((index * 7919) % 200_000)
        file.write [ channel.code, "ID-#{index}", "EST-#{index}", Date.current.strftime("%d/%m/%Y"), Money.format(amount * 3 / 10), "contestação" ].join(";") + "\n"
      end
    end
    reversal = measure.call("envio do arquivo de #{reversal_count} estornos") { service.start(tenant: tenant, user: user, file: reversals_path, mode: :incremental, kind: "reversals") }
    batch.call("conferência de #{reversal_count} estornos", reversal_count) { reversal.checker.run(reversal) }
    puts "  resumo: #{reversal.reload.summary.slice('valid', 'rejected').to_json} efeito: #{reversal.summary['effect'].to_json}"
    batch.call("confirmação de #{reversal_count} estornos", reversal_count) { reversal.confirmer.run(reversal) }
    puts "  situação: #{reversal.reload.status}"
    measure.call("resumo da carteira depois dos estornos") { Portfolio::Summary.new(user).totals }

    exit if ENV["KEEP_DATA"] == "1" # só para investigação (EXPLAIN)
    [ payments_path, reversals_path ].each { |path| File.delete(path) if File.exist?(path) }
    [ PaymentAllocation.where(payment_id: Payment.where(tenant_id: tenant.id).select(:id)), *[ Abatement, Credit, PaymentReversal, Payment, Change ].map { |model| model.unscoped.where(tenant_id: tenant.id) } ].each(&:delete_all)
    MeasureData.wipe_portfolio(tenant.id)
    PaymentChannel.where(tenant_id: tenant.id).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: tenant.id).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end
  desc "V4 de acionamentos: gera N acionamentos num credor de medição e mede ficha, lista, resumo e registro: crm:measure_contacts[acionamentos]"
  task :measure_contacts, %i[attempts] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:attempts].presence || 1_000_000).to_i
    tenant = Tenant.provision!("Medição de acionamentos #{Time.current.strftime('%H%M%S')}")
    user = User.create!(name: "Medição", email_address: "medicao#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    operators = [ user.id ] + 4.times.map { |i| User.create!(name: "Operador #{i}", email_address: "op#{i}-#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24)).id }
    t = tenant.id

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format("%-62s %8.3f s", label, elapsed)
      result
    end

    # 20 mil clientes e N acionamentos espalhados pelos últimos 92 dias, nos 11 resultados, em 5 operadores e 5 canais (insert_all! do modelo, sem auditoria por registro).
    MeasureData.insert(Customer, (1..20_000).map { |g| { tenant_id: t, document: g.to_s.rjust(11, "0"), name: "Cliente #{g}" } })
    first_customer = Customer.where(tenant_id: t).minimum(:id)
    results = tenant.contact_results.ordered.to_a
    channels = %w[phone whatsapp sms email letter]
    measure.call("gerar #{count} acionamentos (com os 3 índices)") do
      now = Time.current
      (1..count).each_slice(10_000) do |slice|
        ContactAttempt.insert_all!(slice.map do |g|
          result = results[g % 11]
          { tenant_id: t, customer_id: first_customer + (g <= 1000 ? 0 : g % 20_000), user_id: operators[g % 5], result_id: result.id, result_kind: result.kind, channel: channels[g % 5],
            text: "Texto de medição #{g}", contacted_at: now - (g % 92).days - (g % 86_400).seconds }
        end, returning: false)
      end
    end
    # Os 1.000 primeiros acionamentos são do primeiro cliente (a ficha pesada).
    heavy = Customer.where(tenant_id: t).order(:id).first
    MeasureData.analyze("contact_attempts")

    measure.call("ficha: primeira página (20) de um cliente com 1.000 acionamentos") { ContactAttempt.history_for(heavy, page: 1).records.to_a }
    measure.call("ficha: contagem para a paginação") { ContactAttempt.history_for(heavy, page: 1).total }

    controller_scope = lambda do |from, to, extra = {}|
      scope = ContactAttempt.visible_to(user, "view_portfolio").where(contacted_at: from..to)
      scope = scope.where(user_id: extra[:operator]) if extra[:operator]
      scope = scope.where(result_kind: extra[:kind]) if extra[:kind]
      scope
    end
    now = Time.current
    measure.call("lista: primeira página (20), últimos 7 dias") { Pagination.new(controller_scope.call(now - 7.days, now).includes(:customer, :result, :user, :tenant).recent, page: 1, per_page: 20).records.to_a }
    measure.call("lista: contagem do período de 7 dias") { Pagination.new(controller_scope.call(now - 7.days, now), page: 1, per_page: 20).total }
    measure.call("lista: período de 92 dias, primeira página") { Pagination.new(controller_scope.call(now - 92.days, now).includes(:customer, :result, :user, :tenant).recent, page: 1, per_page: 20).records.to_a }
    measure.call("lista: período de 92 dias, contagem") { Pagination.new(controller_scope.call(now - 92.days, now), page: 1, per_page: 20).total }
    measure.call("lista: 92 dias filtrada por operador e tipo") do
      Pagination.new(controller_scope.call(now - 92.days, now, operator: operators[1], kind: "no_contact").includes(:customer, :result, :user, :tenant).recent, page: 1, per_page: 20).records.to_a
    end
    measure.call("resumo da carteira (inclui os acionamentos de 7 e 30 dias)") { Portfolio::Summary.new(user).totals }
    measure.call("registrar um acionamento (regras, gravação e histórico)") do
      Contacts::Recorder.new(user).record(heavy, { channel: "phone", result_id: results.last.id, text: "medição do registro" })
    end

    ContactAttempt.where(tenant_id: t).delete_all
    [ Change, ContractCustomer ].each { |model| model.where(tenant_id: t).delete_all if model.column_names.include?("tenant_id") }
    Customer.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    User.where(id: operators).destroy_all
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 da carteira revista (05): carteira de N linhas, 10% com pagamento e mudança de valor na segunda carga: crm:measure_discrepancies[linhas]"
  task :measure_discrepancies, %i[lines] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    lines = (args[:lines].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de divergências #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      puts format("%-55s %8.2f s   (pico de memória %d MB)", label, elapsed, peak)
      result
    end

    # Segunda carga: 10% dos títulos mudam de valor (metade cai abaixo do pago), os demais vêm iguais.
    write_file = lambda do |path, changed|
      today = Date.current
      File.open(path, "wb") do |file|
        file.write "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n"
        lines.times do |i|
          customer = i / 2
          days = 1 + ((customer * 37 + i * 11) % 500)
          cents = 5000 + ((i * 7919) % 250_000)
          cents = ((i % 20).zero? ? cents / 4 : cents * 2 / 3) if changed && (i % 10).zero?
          file.write [ FakeData.cpf(customer), FakeData.name(customer), "(11) 9#{(customer % 100_000_000).to_s.rjust(8, '0')}", "cliente#{customer}@exemplo.com.br",
                       "CT-#{customer.to_s.rjust(7, '0')}", "NF-#{customer}/#{i % 2 + 1}", (today - (days - 20)).strftime("%d/%m/%Y"), Money.format(cents), "Mensalidade" ].join(";") + "\n"
        end
      end
    end

    first = Rails.root.join("tmp", "div1-#{t}.csv").to_s
    second = Rails.root.join("tmp", "div2-#{t}.csv").to_s
    write_file.call(first, false)
    write_file.call(second, true)
    service = Portfolio::ImportService.new
    import = service.start(tenant: tenant, user: user, file: first, mode: :incremental)
    measure.call("1ª carga: conferência de #{lines} linhas (sem pagamentos)") { import.checker.run(import) }
    measure.call("1ª carga: confirmação de #{lines} linhas") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}"

    # Pagamento parcial (um terço) em 10% dos títulos, direto no banco: o que se mede aqui é a carga, não o pagamento (V4 da camada 6).
    # São os títulos das linhas múltiplas de 10 do arquivo (número `NF-<cliente>/1` com cliente múltiplo de 5).
    Bill.where(tenant_id: t).where("number like '%/1' and split_part(substring(number from 4), '/', 1)::int % 5 = 0").update_all("paid_cents = amount_cents / 3")
    MeasureData.analyze("bills")

    import = service.start(tenant: tenant, user: user, file: second, mode: :incremental)
    measure.call("2ª carga: conferência (10% com pagamento e valor novo)") { import.checker.run(import) }
    puts "  divergências: #{import.reload.summary['discrepancies']['count']}"
    measure.call("2ª carga: confirmação") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; divergências abertas: #{ValueDiscrepancy.where(tenant_id: t, status: 'open').count}; versões: #{BillValueVersion.where(tenant_id: t).count}"

    measure.call("resumo da carteira (crédito, excedente e recuperado)") { Portfolio::Summary.new(user).totals }
    measure.call("lista de clientes (primeira página)") { Portfolio::Query.new(user).customers.limit(20).to_a }
    measure.call("lista de divergências (primeira página)") { Pagination.new(ValueDiscrepancy.visible_to(user, "confirm_payments").includes(bill: :customer).recent, page: 1, per_page: 20).records.to_a }
    measure.call("lista de divergências (contagem das abertas)") { ValueDiscrepancy.where(tenant_id: t, status: "open").count }
    some = Customer.where(tenant_id: t).order(:id).offset(5).first
    measure.call("ficha do cliente (títulos e excedente do contrato)") do
      bills = Bill.where(customer: some).to_a
      BillValueVersion.where(bill_id: bills.map(&:id)).group(:bill_id).count
      Bill.where(contract_id: some.contracts.ids).where("paid_cents > amount_cents").to_a
    end
    measure.call("histórico de um título") { Portfolio::BillHistory.new(Bill.where(customer: some).first).events }

    [ first, second ].each { |path| File.delete(path) if File.exist?(path) }
    MeasureData.clear(t, %w[value_discrepancies reported_surcharges bill_value_versions changes])
    MeasureData.wipe_portfolio(t)
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end
  desc "V4 de cadastros: carga de N linhas com 3 telefones, 2 e-mails e endereço, duas vezes (a segunda com dados mantidos), ficha com 50 contatos: crm:measure_registry[linhas]"
  task :measure_registry, %i[lines] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    lines = (args[:lines].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de cadastros #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    tenant.update!(phone: "(11) 3000-1000", legal_name: "Credor de medição")
    ActiveJob::Base.queue_adapter = :test

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      puts format("%-58s %8.2f s   (pico de memória %d MB)", label, elapsed, peak)
      result
    end

    # Um título por cliente, com 3 telefones (1% com o do credor), 2 e-mails e o endereço completo: até 6 contatos por linha.
    write_file = lambda do |path, new_phones|
      today = Date.current
      File.open(path, "wb") do |file|
        file.write "documento;nome;telefone;telefone2;telefone3;email;email2;contrato;titulo;vencimento;valor;descricao;logradouro;numero;bairro;cidade;uf;cep\n"
        lines.times do |i|
          days = 1 + ((i * 37) % 500)
          phones = [ "(11) 9#{(i % 100_000_000).to_s.rjust(8, '0')}", "(21) 3#{((i + 7) % 10_000_000).to_s.rjust(7, '0')}", (i % 100).zero? ? "(11) 3000-1000" : "(31) 9#{((i + 11) % 100_000_000).to_s.rjust(8, '0')}" ]
          phones[1] = "(41) 9#{(i % 100_000_000).to_s.rjust(8, '0')}" if new_phones && (i % 20).zero?
          file.write [ FakeData.cpf(i), FakeData.name(i), *phones, "cliente#{i}@exemplo.com.br", "outro#{i}@exemplo.com.br", "CT-#{i.to_s.rjust(7, '0')}", "NF-#{i}/1",
                       (today - (days - 20)).strftime("%d/%m/%Y"), Money.format(5000 + ((i * 7919) % 250_000)), "Mensalidade", "Rua #{i % 900} de Teste", (i % 400) + 1, "Centro",
                       "São Paulo", "SP", "01#{(i % 1000).to_s.rjust(3, '0')}-000" ].join(";") + "\n"
        end
      end
    end

    # SQL_LENTO=2 mostra os comandos que levam mais de 2 s (para achar onde o tempo vai).
    if ENV["SQL_LENTO"]
      ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, started, finished, _id, payload|
        puts format("    [sql %.1f s] %s", finished - started, payload[:sql].squish[0, 110]) if finished - started > (ENV["SQL_LENTO"].to_f)
      end
    end
    first = Rails.root.join("tmp", "cad1-#{t}.csv").to_s
    second = Rails.root.join("tmp", "cad2-#{t}.csv").to_s
    write_file.call(first, false)
    write_file.call(second, true)
    service = Portfolio::ImportService.new
    import = service.start(tenant: tenant, user: user, file: first, mode: :incremental)
    measure.call("1ª carga: conferência de #{lines} linhas (até 6 contatos)") { import.checker.run(import) }
    puts "  avisos: #{import.reload.summary['contact_warnings']}; contatos lidos: #{import.summary['contacts']}"
    measure.call("1ª carga: confirmação de #{lines} linhas") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; contatos: #{CustomerContact.where(tenant_id: t).count}; inválidos (do credor): #{CustomerContact.where(tenant_id: t, status: 'invalid').count}"

    # Antes da 2ª carga: 10% dos clientes com nome corrigido na tela e um contato em "não perturbe" que a carga traz de novo.
    Customer.where(tenant_id: t).where("id % 10 = 0").update_all("name = name || ' Souza', name_kept = true")
    CustomerContact.where(tenant_id: t, kind: "phone").where("customer_id % 10 = 0 and key like '11%'").update_all(status: "do_not_disturb", do_not_disturb_on: Date.current, kept_by_tenant: true)
    MeasureData.analyze("customers", "customer_contacts")

    import = service.start(tenant: tenant, user: user, file: second, mode: :incremental)
    measure.call("2ª carga: conferência (dados mantidos, 5% com telefone novo)") { import.checker.run(import) }
    kept = import.reload.summary["kept_by_tenant"]
    puts "  mantidos: #{kept['names']['count']} nomes, #{kept['contacts']['count']} contatos"
    measure.call("2ª carga: confirmação (atualiza a data de todos os contatos)") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; contatos: #{CustomerContact.where(tenant_id: t).count}"

    # Ficha com 50 contatos: as consultas que a tela faz.
    some = Customer.where(tenant_id: t).order(:id).offset(5).first
    50.times { |i| CustomerContact.create!(tenant_id: t, customer: some, kind: "phone", key: "5#{i.to_s.rjust(9, '0')}", value: "(51) 9#{i.to_s.rjust(7, '0')}", origin: "screen", status: i.even? ? "valid" : "invalid") }
    measure.call("ficha com #{some.contacts.count} contatos (consultas da tela)") do
      contacts = some.contacts.includes(:updated_by).to_a
      CustomerContact.top_valid(some, contacts)
      CustomerContact.listed(contacts)
      Change.where("(subject_type = 'customer' and subject_id = ? and field = 'name') or (subject_type = 'customer_contact' and subject_id in (?))", some.id, contacts.map(&:id)).order(occurred_at: :desc).limit(50).to_a
    end
    measure.call("sugestões do acionamento (contatos válidos do canal)") { some.contacts.status_valid.where(kind: "phone").order(:kind, :id).pluck(:value) }
    measure.call("R126: o credor muda o telefone (varre os contatos do credor)") { Registry::TenantEditor.new(user).update(tenant, phone: "(11) 3000-1000".sub("3000", "3001")) }
    measure.call("lista de clientes (primeira página)") { Portfolio::Query.new(user).customers.limit(20).to_a }
    measure.call("resumo da carteira") { Portfolio::Summary.new(user).totals }

    [ first, second ].each { |path| File.delete(path) if File.exist?(path) }
    MeasureData.clear(t, %w[bill_value_versions reported_surcharges changes customer_contacts])
    MeasureData.wipe_portfolio(t)
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos direitos do titular (07): N clientes com título pago há 6 anos, contatos, acionamentos e pagamentos; mede exportar, anonimizar um, previsão e a tarefa diária: crm:measure_titular[clientes]"
  task :measure_titular, %i[customers] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:customers].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de direitos do titular #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Um cliente por linha, um contrato por cliente, um título pago há 6 anos com o pagamento, 3 contatos, 1 acionamento com texto e histórico (insert_all! dos modelos).
    today = Date.current
    MeasureData.portfolio(t, count, document: ->(i) { i.to_s.rjust(11, "0") },
                                         bill: ->(i, _n) { { number: "NF-#{i}", due_date: today - 2300, amount_cents: 10_000, paid_cents: 10_000, paid_on: today - 2200, status: "paid", description: "Mensalidade de Cliente #{i}" } })
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "MEDICAO", description: "Canal de medição")
    people = Customer.where(tenant_id: t).order(:id).pluck(:id, :document, :name)
    bills = Bill.where(tenant_id: t).pluck(:customer_id, :id, :number).to_h { |customer, id, number| [ customer, [ id, number ] ] }
    MeasureData.insert(Payment, people.map do |id, document, _name|
      bill_id, number = bills.fetch(id)
      { tenant_id: t, channel_id: channel.id, identifier: "P-#{bill_id}", document: document, bill_number: number, bill_id: bill_id, paid_on: today - 2200, amount_cents: 10_000,
        payment_method: "pix", status: "applied", applied_cents: 10_000 }
    end)
    MeasureData.insert(CustomerContact, people.flat_map do |id, _document, _name|
      %w[phone email address].map { |kind| { tenant_id: t, customer_id: id, kind: kind, key: "#{kind}#{id}", value: "contato #{kind} #{id}", origin: "load", status: "valid" } }
    end)
    result = ContactResult.where(tenant_id: t).first
    MeasureData.insert(ContactAttempt, people.map do |id, _document, name|
      { tenant_id: t, customer_id: id, result_id: result.id, result_kind: result.kind, channel: "phone", contact_used: "contato phone #{id}", text: "Falou com #{name}", contacted_at: Time.current - 2200.days }
    end)
    MeasureData.insert(Change, people.map { |id, _document, name| { tenant_id: t, subject_type: "customer", subject_id: id, event: "updated", field: "name", before: "Antigo #{name}", after: name, occurred_at: Time.current } })
    MeasureData.analyze("customers", "bills", "payments", "contracts", "contract_customers", "contact_attempts", "customer_contacts", "changes")
    puts "#{count} clientes criados no credor de medição"

    # Exportação e anonimização de um cliente com 1.000 acionamentos (limites da especificação: 3 s e 5 s).
    heavy = Customer.where(tenant_id: t).order(:id).first
    MeasureData.insert(ContactAttempt, (1..1000).map do |i|
      { tenant_id: t, customer_id: heavy.id, result_id: result.id, result_kind: result.kind, channel: "phone", contact_used: "contato phone", text: "Texto do acionamento #{i}",
        contacted_at: Time.current - 2200.days + i.minutes }
    end)
    measure.call("exportar um cliente com 1.000 acionamentos", 3) { Titular::Exporter.new(heavy).to_h }
    measure.call("anonimizar um cliente com 1.000 acionamentos (a pedido)", 5) { Titular::Anonymizer.on_request(heavy, actor: user, reason: "medição", document: heavy.document) }

    due = measure.call("previsão de 30 dias e vencidos (consulta de conjunto)") { Titular::Retention.due([ t ], within: 30).count }
    puts "  vencidos ou previstos: #{due}"
    measure.call("página de guarda: primeira página da previsão (20)") { Pagination.new(Titular::Retention.due([ t ], within: 30).order("due_on, id"), page: 1, per_page: 20).records.to_a }
    run = measure.call("tarefa diária: anonimiza #{count - 1} clientes vencidos", 600) { Titular::RetentionRun.new(tenant).call }
    puts "  execução: #{run.status}, #{run.processed} anonimizados, #{run.failed} falhas"
    puts "  clientes ainda identificados: #{Customer.where(tenant_id: t, anonymized_at: nil).count}"
    puts "  dado pessoal restante nos acionamentos: #{ContactAttempt.where(tenant_id: t).where("text like 'Falou com%' or text like 'Texto do%'").count}"

    MeasureData.clear(t, %w[bill_value_versions changes customer_contacts contact_attempts payments task_runs])
    MeasureData.wipe_portfolio(t)
    PaymentChannel.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos segmentos (08): N contratos (1 cliente e 2 títulos cada) e 5 segmentos; mede conferência, confirmação, recálculo diário, aba, lista e ficha: crm:measure_segments[contratos]"
  task :measure_segments, %i[contracts] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:contracts].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de segmentos #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Um cliente por contrato (60% CPF, 40% CNPJ), dois títulos de produtos diferentes, atrasos de 1 a 400 dias (insert_all! dos modelos).
    MeasureData.portfolio(t, count, document: ->(i) { i % 5 < 3 ? i.to_s.rjust(11, "0") : i.to_s.rjust(14, "0") }, contract_age: ->(i) { i % 700 },
                          bills_per: 2, bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - (1 + (i * 37 + n * 11) % 400), amount_cents: 5000 + (i * 7919 + n * 131) % 250_000, product: n == 1 ? "Mensalidade" : "Cartão" } })
    MeasureData.analyze("customers", "contracts", "bills", "contract_customers")
    puts "#{count} contratos criados no credor de medição"

    # Cinco segmentos (4 com critérios e o Demais), no mesmo desenho da especificação.
    base = { tenant: tenant }
    Segment.create!(**base, name: "Varejo PF recente", position: 1, person_type: "person", min_overdue_days: 1, max_overdue_days: 90, max_balance_cents: 500_000)
    Segment.create!(**base, name: "PF", position: 2, person_type: "person")
    Segment.create!(**base, name: "Muito vencido", position: 3, min_overdue_bills: 2, min_overdue_percent: 50)
    Segment.create!(**base, name: "Cartões", position: 4, products: [ "cartao" ])
    proposal = Segments::Proposal.current(tenant)
    token = proposal.token
    measure.call("recálculo inicial (diário) dos #{count} contratos", 120) { Segments::Recalculation.new(tenant).call }
    MeasureData.analyze("contract_segments", "contracts")
    puts "  contratos por segmento: #{Segment.where(tenant_id: t).ordered.map { |s| "#{s.name}=#{Contract.where(segment_id: s.id).count}" }.join(', ')}"

    changed = Segments::Proposal.current(tenant).with_created(Segment.new(tenant: tenant, name: "Recentes", min_age_days: 0, max_age_days: 200).tap(&:valid?))
    4.times { changed = changed.with_moved(Segments::Proposal::NEW_ID, "up") }
    impact = measure.call("conferir uma mudança de segmentos", 10) { Segments::Impact.new(changed) }
    puts "  entram em outros segmentos: #{impact.total} contratos"
    measure.call("confirmar a mudança de segmentos (grava e recalcula)", 10) { Segments::Applier.new(user).confirm(tenant, changed.token) }
    measure.call("política de produto: conferir a mudança para 'qualquer título'", 10) { Segments::Impact.new(Segments::Proposal.current(tenant).with_policy("any_bill")) }
    measure.call("recálculo diário depois da mudança (nada muda)", 120) { Segments::Recalculation.new(tenant).call }

    measure.call("aba Segmentos: totais por segmento") { Segments::Totals.new([ tenant ]).call }
    query = Portfolio::Query.new(user)
    measure.call("lista de clientes com a coluna Segmento (primeira página)") { query.customers.limit(20).to_a.tap { |page| query.segment_names(page.map(&:id)) } }
    measure.call("lista de clientes (contagem total)") { query.customers.except(:select, :order).count }
    measure.call("lista filtrada por segmento (primeira página)") { query.customers(segment: Segment.where(tenant_id: t, name: "Recentes").pick(:id)).limit(20).to_a.tap { |page| query.segment_names(page.map(&:id)) } }
    measure.call("lista filtrada por 'sem segmento' (primeira página)") { query.customers(segment: "none", search: "Cliente 1").limit(20).to_a }
    some = Customer.where(tenant_id: t).order(:id).first
    measure.call("ficha: segmento e histórico do contrato") { ContractSegment.where(contract_id: some.contracts.select(:id)).includes(:segment).order(since: :desc).limit(100).to_a }

    if ENV["KEEP"] == "1"
      puts "KEEP=1: credor de medição #{t} mantido para análise (EXPLAIN)"
      next
    end
    MeasureData.clear(t, %w[changes task_runs])
    MeasureData.wipe_portfolio(t)
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos encargos (09): N contratos (2 títulos vencidos cada), 5 segmentos com regras diferentes, índices desde 2000 e P pagamentos; mede recálculo, conferência, confirmação, lista, ficha, resumo e a baixa por componente: crm:measure_charges[contratos,pagamentos]"
  task :measure_charges, %i[contracts payments] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:contracts].presence || 10_000).to_i
    payments = (args[:payments].presence || count).to_i
    tenant = Tenant.provision!("Medição de encargos #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Índices mensais desde janeiro de 2000 (valores fictícios) para as cinco séries; a medição usa o mesmo banco dos testes.
    months = (Date.new(2000, 1, 1)..Date.current.beginning_of_month.prev_month).select { |d| d.day == 1 }
    saved_rates = IndexRate.all.map(&:attributes)
    IndexRate.delete_all
    IndexRate.insert_all!(IndexRate::SERIES.flat_map { |series| months.each_with_index.map { |month, i| { series: series, month: month, value: (0.2 + (i % 7) * 0.11).round(6), partial: false, fetched_at: Time.current } } })

    MeasureData.portfolio(t, count, contract_age: ->(i) { i % 700 }, bills_per: 2,
                          bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - (1 + (i * 37 + n * 11) % 400), amount_cents: 5000 + (i * 7919 + n * 131) % 250_000, product: n == 1 ? "Mensalidade" : "Cartão" } })
    MeasureData.analyze("customers", "contracts", "bills", "contract_customers")
    puts "#{count} contratos (#{count * 2} títulos vencidos) criados no credor de medição"

    tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, charge_index: "ipca")
    Segment.catch_all_of(tenant).update!(interest_kind: "fixed", fees_pct: 10, fees_in_contract: true)
    Segment.create!(tenant: tenant, name: "Varejo PF recente", position: 1, person_type: "person", min_overdue_days: 1, max_overdue_days: 90, interest_kind: "fixed", index_code: "ipca")
    Segment.create!(tenant: tenant, name: "PF", position: 2, person_type: "person", interest_kind: "fixed", interest_pct: 2, index_code: "inpc")
    Segment.create!(tenant: tenant, name: "Pessoa jurídica", position: 3, person_type: "company", interest_kind: "legal", index_code: "ipca")
    Segment.create!(tenant: tenant, name: "Muito vencido", position: 4, min_overdue_bills: 2, min_overdue_percent: 50, interest_kind: "fixed", interest_form: "compound", index_code: "igpm")
    Charges::RuleHistory.record!(tenant, since: Date.current - 400)
    Segments::Recalculation.new(tenant).apply
    MeasureData.analyze("contract_segments", "contracts")

    measure.call("recálculo diário do valor atualizado (#{count * 2} títulos)", 120) { Charges::Recalculation.new(tenant).apply }
    puts "  títulos com valor atualizado: #{BillValuation.where(tenant_id: t).count}; total R$ #{Money.format(BillValuation.where(tenant_id: t).sum(:total_cents))}"
    MeasureData.analyze("bill_valuations")

    measure.call("recálculo diário de novo (medido sem a carga fria)", 120) { Charges::Recalculation.new(tenant).apply }
    impact_rule = measure.call("conferir uma mudança de regra em 'PF' (juros 2% → 3%)", 10) do
      segment = Segment.find_by!(tenant_id: t, name: "PF")
      proposal = Segments::Proposal.current(tenant).with_updated(segment.tap { |record| record.interest_pct = 3 })
      Charges::Impact.new(proposal).tap(&:rows)
    end
    puts "  diferença: R$ #{Money.format(impact_rule.total_difference_cents)} em #{impact_rule.rows.sum(&:customers)} clientes"
    measure.call("conferir uma mudança de política ('Índice negativo' sempre; base toda)", 10) { Charges::Impact.new(Segments::Proposal.current(tenant).with_charges("negative_index_policy" => "always")).tap(&:rows) }
    measure.call("confirmar a mudança de regra (grava; o recálculo vai para o segundo plano)", 10) do
      Segments::Applier.new(user).confirm(tenant, Segments::Proposal.current(tenant).with_charges("charge_interest_pct" => "1.5").token)
    end
    measure.call("recálculo depois da confirmação", 120) { Charges::Recalculation.new(tenant).apply }

    query = Portfolio::Query.new(user)
    measure.call("lista de clientes com a coluna Atualizado (primeira página)", 3) { query.customers.limit(20).to_a.tap { |page| query.updated_totals(page.map(&:id)); query.segment_names(page.map(&:id)) } }
    measure.call("resumo com atualizado, faixas e segmentos", 10) { Portfolio::Summary.new(user).totals }
    some = Bill.where(tenant_id: t).order(:id).first
    measure.call("ficha: memória de cálculo de um título", 1) do
      input = Charges::Reader.new(tenant, today: Date.current, bill_ids: [ some.id ]).to_enum(:each_batch).flat_map(&:itself).first
      Charges::Valuation.new(tables: Charges::RuleSet.tables(tenant, Date.current), rules: Charges::RuleSet.rules(tenant), demais_id: Charges::RuleSet.demais_id(tenant),
                             versions: Charges::RuleHistory.lookup(tenant)).call(input, memory: true)
    end

    # Baixa por componente (R226): P pagamentos, 60% quitam o valor atualizado, 25% parciais, 15% de valor original.
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "341-1234-56789", description: "Conta de medição")
    path = Rails.root.join("tmp", "pagamentos-encargos-#{t}.csv").to_s
    valuations = BillValuation.where(tenant_id: t).order(:bill_id).limit(payments).pluck(:bill_id, :total_cents, :principal_cents)
    numbers = Bill.where(id: valuations.map(&:first)).pluck(:id, :number, :customer_id).to_h { |id, number, customer| [ id, [ number, customer ] ] }
    documents = Customer.where(id: numbers.values.map(&:last)).pluck(:id, :document).to_h
    File.open(path, "wb") do |file|
      file.write "canal;identificador;documento;titulo;data_pagamento;valor;meio;estado_final\n"
      valuations.each_with_index do |(bill_id, total, principal), index|
        value = case index % 20 when 0..11 then total when 12..16 then total / 2 else principal end
        number, customer = numbers.fetch(bill_id)
        # 11, R226: 5% das linhas (um terço das de valor original) trazem o estado final "quitado", e a diferença vira abatimento do credor.
        final_state = index % 20 == 17 ? "quitado" : ""
        file.write [ channel.code, "ID-#{index}", documents.fetch(customer), number, (Date.current - 1).strftime("%d/%m/%Y"), Money.format(value), "pix", final_state ].join(";") + "\n"
      end
    end
    service = Portfolio::ImportService.new
    import = service.start(tenant: tenant, user: user, file: path, mode: :incremental, kind: "payments")
    measure.call("conferência de #{valuations.size} pagamentos com encargos", 120) { import.checker.run(import) }
    puts "  efeito: #{import.reload.summary['effect'].to_json}"
    measure.call("confirmação de #{valuations.size} pagamentos com baixa por componente", 120) { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; alocações: #{PaymentAllocation.joins(:bill).where(bills: { tenant_id: t }).count}"
    measure.call("recálculo depois dos pagamentos", 120) { Charges::Recalculation.new(tenant).apply }

    File.delete(path) if File.exist?(path)
    PaymentAllocation.where(payment_id: Payment.where(tenant_id: t).select(:id)).delete_all
    MeasureData.clear(t, %w[bill_valuations abatements credits payment_reversals payments changes task_runs bill_value_versions value_discrepancies])
    MeasureData.wipe_portfolio(t)
    PaymentChannel.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    IndexRate.delete_all
    IndexRate.insert_all!(saved_rates.map { |row| row.except("id") }) if saved_rates.any?
    puts "credor de medição apagado"
  end

  desc "V4 das promessas (10): P promessas abertas e pagamentos (10% de promessa, o resto direto), mede conferência, confirmação, tarefa diária, formulário com 10 títulos, painel e lista de pendentes: crm:measure_promises[promessas,pagamentos]"
  task :measure_promises, %i[promises payments] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    promises = (args[:promises].presence || 50_000).to_i
    payments = (args[:payments].presence || 200_000).to_i
    promise_payments = payments / 10
    direct = payments - promise_payments
    customers = promises + direct
    tenant = Tenant.provision!("Medição de promessas #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = MeasureData.profile(label) { work.call }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Encargos do exemplo (multa 2%, juros 1% ao mês, IPCA) e índices desde 2000, como na V4 dos encargos; o teste guarda e devolve os índices.
    months = (Date.new(2000, 1, 1)..Date.current.beginning_of_month.prev_month).select { |d| d.day == 1 }
    saved_rates = IndexRate.all.map(&:attributes)
    IndexRate.delete_all
    IndexRate.insert_all!(IndexRate::SERIES.flat_map { |series| months.each_with_index.map { |month, i| { series: series, month: month, value: (0.2 + (i % 7) * 0.11).round(6), partial: false, fetched_at: Time.current } } })
    tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, charge_index: "ipca", promise_sequence: promises)
    Segment.catch_all_of(tenant).update!(interest_kind: "fixed")
    Charges::RuleHistory.record!(tenant, since: Date.current - 400)

    MeasureData.portfolio(t, customers, bill: ->(i, _n) { { number: "NF-#{i}", due_date: Date.current - (30 + (i % 60)), amount_cents: 5000 + (i * 7919) % 250_000 } })
    MeasureData.analyze("customers", "contracts", "bills", "contract_customers")
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "341-1234-56789", description: "Conta de medição")
    result = tenant.contact_results.find_by!(allows_promise: true, name: "Prometeu pagar")
    segment = Segment.catch_all_of(tenant)
    first_ids = Customer.where(tenant_id: t).order(:id).limit(promises).pluck(:id)
    puts "#{customers} clientes e títulos criados; #{promises} promessas abertas, #{promise_payments} pagamentos de promessa e #{direct} diretos"

    # Promessas abertas com prazo já vencido (a tarefa diária quebra as que o arquivo não cumprir), ligadas ao título do cliente (insert_all! dos modelos).
    contracts_of = ContractCustomer.where(customer_id: first_ids).pluck(:customer_id, :contract_id).to_h
    now = Time.current
    first_ids.each_slice(10_000) do |slice|
      ContactAttempt.insert_all!(slice.map do |customer_id|
        { tenant_id: t, customer_id: customer_id, contract_id: contracts_of.fetch(customer_id), user_id: user.id, result_id: result.id, result_kind: "spoke_with_customer", channel: "phone", contacted_at: now - 12.days }
      end, returning: false)
    end
    policies = { tolerance_days: 3, counting: "promise_only", min_paid_pct: nil, after_break: "fulfilled", grace_days: 0, partial: "prevails", limit_days: 30, ceiling_days: 30 }
    bills_of = Bill.where(tenant_id: t, customer_id: first_ids).pluck(:customer_id, :id, :amount_cents).to_h { |customer_id, id, cents| [ customer_id, [ id, cents ] ] }
    attempts = ContactAttempt.where(tenant_id: t).order(:id).pluck(:id, :customer_id, :contract_id)
    attempts.each_slice(10_000).with_index do |slice, slice_index|
      PaymentPromise.insert_all!(slice.each_with_index.map do |(attempt_id, customer_id, contract_id), index|
        { tenant_id: t, customer_id: customer_id, contract_id: contract_id, contact_attempt_id: attempt_id, user_id: user.id, segment_id: segment.id,
          number: "PRM-#{(slice_index * 10_000 + index + 1).to_s.rjust(6, '0')}", state: "open", payment_method: "pix", promised_on: Date.current - 5, contacted_on: Date.current - 12,
          policies: policies, total_cents: bills_of.fetch(customer_id).last }
      end, returning: false)
    end
    promise_ids = PaymentPromise.where(tenant_id: t).pluck(:customer_id, :id).to_h
    MeasureData.insert(PaymentPromiseBill, promise_ids.map do |customer_id, promise_id|
      bill_id, cents = bills_of.fetch(customer_id)
      { promise_id: promise_id, bill_id: bill_id, principal_cents: cents, total_cents: cents, paid: {}, held: true }
    end)
    MeasureData.analyze("payment_promises", "payment_promise_bills", "contact_attempts")

    # Arquivo: 10% pelo número da promessa (valor do título, no prazo) e o resto pagamento direto de outros clientes.
    path = Rails.root.join("tmp", "pagamentos-promessas-#{t}.csv").to_s
    promise_rows = PaymentPromise.where(tenant_id: t).joins(:customer).order(:id).limit(promise_payments).pluck(:number, "customers.document", :total_cents).map { |values| values.then { |n, d, c| { "number" => n, "document" => d, "total" => c } } }
    direct_rows = Bill.where(tenant_id: t).where("bills.customer_id > ?", first_ids.last).joins(:customer).order("bills.id").limit(direct).pluck(:number, "customers.document", :amount_cents).map { |n, d, c| { "number" => n, "document" => d, "total" => c } }
    pay_date = (Date.current - 6).strftime("%d/%m/%Y")
    File.open(path, "wb") do |file|
      file.write "canal;identificador;documento;titulo;data_pagamento;valor;meio\n"
      (promise_rows.map { |row| [ row, "pix" ] } + direct_rows.map { |row| [ row, "boleto" ] }).each_with_index do |(row, method), index|
        file.write [ channel.code, "ID-#{index}", row.fetch("document"), row.values.first, pay_date, Money.format(row.values.last.to_i), method ].join(";") + "\n"
      end
    end
    import = Portfolio::ImportService.new.start(tenant: tenant, user: user, file: path, mode: :incremental, kind: "payments")
    measure.call("conferência de #{promise_rows.size + direct_rows.size} pagamentos (#{promise_rows.size} de promessa)", 120) { import.checker.run(import) }
    puts "  efeito: #{import.reload.summary['effect'].to_json}"
    measure.call("confirmação dos pagamentos, com a avaliação das promessas", 120) { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; promessas cumpridas: #{PaymentPromise.where(tenant_id: t, state: 'fulfilled').count}"

    measure.call("tarefa diária (quebra as abertas vencidas)", 120) { Promises::Daily.new(tenant).apply }
    puts "  quebradas: #{PaymentPromise.where(tenant_id: t, state: 'broken').count}; ainda abertas: #{PaymentPromise.where(tenant_id: t, state: 'open').count}"

    # Formulário: valor de uma promessa de 10 títulos (R186, até 1 s).
    big = Customer.create!(tenant: tenant, document: FakeData.cpf(customers + 10), name: "Cliente de 10 títulos")
    contract = Contract.create!(tenant: tenant, code: "CT-DEZ-TITULOS")
    ContractCustomer.create!(contract: contract, customer: big)
    ten = (1..10).map { |n| Bill.create!(tenant: tenant, contract: contract, customer: big, number: "T-#{n}", due_date: Date.current - n * 20, amount_cents: 50_000 + n * 1_000) }
    measure.call("formulário: valor da promessa de 10 títulos", 1) { Promises::Pricing.quote(tenant, ten, Date.current + 20) }
    measure.call("painel: resumo do credor com as promessas", 10) { Portfolio::Summary.new(user).totals }
    measure.call("lista de pendentes e número do menu", 1) { Promises::Pending.for(user).count }

    File.delete(path) if File.exist?(path)
    PaymentAllocation.where(payment_id: Payment.where(tenant_id: t).select(:id)).delete_all
    PaymentPromiseBill.where(promise_id: PaymentPromise.where(tenant_id: t).select(:id)).delete_all
    Payment.where(tenant_id: t).update_all(promise_id: nil)
    MeasureData.clear(t, %w[reversal_waits credits payment_reversals payments changes task_runs bill_value_versions value_discrepancies bill_valuations payment_promises contact_attempts])
    MeasureData.wipe_portfolio(t)
    PaymentChannel.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    IndexRate.delete_all
    IndexRate.insert_all!(saved_rates.map { |row| row.except("id") }) if saved_rates.any?
    puts "credor de medição apagado"
  end

  desc "V4 dos acordos (11): A acordos efetivados (entrada paga e três parcelas), 10% com parcela vencida há mais dos dias de quebra e 10% em atraso dentro dos dias; mede a tarefa diária, o pagamento de parcelas pelo número e a simulação com 100 títulos: crm:measure_agreements[acordos,pagamentos]"
  task :measure_agreements, %i[agreements payments] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:agreements].presence || 50_000).to_i
    payments = (args[:payments].presence || 20_000).to_i
    tenant = Tenant.provision!("Medição de acordos #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = MeasureData.profile(label) { work.call }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end
    tenant.update!(legal_name: "Medição de acordos Ltda")
    tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, installment_rate_pct: 1.5, installment_method: "price")
    segment = Segment.catch_all_of(tenant)

    # Um cliente por acordo, com o título original já renegociado (insert_all! dos modelos).
    customer_ids = MeasureData.portfolio(t, count, bill: ->(i, _n) { { number: "NF-#{i}", due_date: Date.current - 200, amount_cents: 120_000, status: "renegotiated" } })
    MeasureData.analyze("customers", "contracts", "bills", "contract_customers")
    terms = { segment: { id: segment.id, name: segment.name, tolerance_days: 3, break_days: 30 }, square: { holidays: [] }, parameters: { late_rule: { fine: 0.02, rate: 0.01, form: "simple", convention: "thirty", fine_base: "corrected", index: "", fees: 0.0 } },
              policies: { break_form: "installments_follow", late_charges: "by_parameters", minimum_to_break: { kind: "cents", value: 0 }, tolerance_agreement: { kind: "cents", value: 100 }, early_payment: "discounts", effectuation: "payment", reactivation: "reactivates" } }
    today = Date.current
    now = Time.current
    originals = Bill.where(tenant_id: t).pluck(:customer_id, :id, :contract_id).to_h { |customer, id, contract| [ customer, [ id, contract ] ] }
    customer_ids.each_slice(10_000).with_index do |slice, slice_index|
      Agreement.insert_all!(slice.each_with_index.map do |customer_id, index|
        { tenant_id: t, customer_id: customer_id, segment_id: segment.id, number: "ACD-#{(slice_index * 10_000 + index + 1).to_s.rjust(6, '0')}", state: "active_on_time", mode: "installments",
          built_on: today - 60, valid_until: today - 55, base_cents: 120_000, discount_cents: 0, value_cents: 120_000, net_cents: 120_000, down_payment_cents: 30_000, down_payment_due: today - 50,
          installments_count: 3, installment_method: "none", total_cents: 120_000, effectuated_at: now - 50.days, effectuated_by: "payment", terms: terms }
      end, returning: false)
    end
    agreements = Agreement.where(tenant_id: t).pluck(:customer_id, :id, :number).to_h { |customer, id, number| [ customer, [ id, number ] ] }
    MeasureData.insert(AgreementBill, customer_ids.map do |customer_id|
      bill_id, contract_id = originals.fetch(customer_id)
      { agreement_id: agreements.fetch(customer_id).first, bill_id: bill_id, contract_id: contract_id, base: {}, discount: {}, credit: {}, value_cents: 120_000, amount_cents: 120_000, paid_cents: 0, held: true }
    end)
    # Entrada paga e três parcelas de R$ 300,00: 10% com a primeira parcela vencida há 40 dias (quebra), 10% há 5 dias (em atraso), o resto a vencer.
    due_of = { 0 => ->(_) { today - 50 }, 1 => ->(id) { id % 10 == 0 ? today - 40 : (id % 10 == 1 ? today - 5 : today + 10) }, 2 => ->(_) { today + 40 }, 3 => ->(_) { today + 70 } }
    due_of.each do |number, due|
      status = number.zero? ? "paid" : "active"
      MeasureData.insert(Bill, customer_ids.map do |customer_id|
        agreement_id, agreement_number = agreements.fetch(customer_id)
        bill_id, contract_id = originals.fetch(customer_id)
        due_on = due.call(customer_id)
        { tenant_id: t, contract_id: contract_id, customer_id: customer_id, number: "#{agreement_number}-#{number.to_s.rjust(2, '0')}", due_date: due_on, amount_cents: 30_000,
          paid_cents: status == "paid" ? 30_000 : 0, status: status, kind: "agreement", agreement_id: agreement_id,
          composition: { items: [ { bill_id: bill_id, component: "principal", cents: 30_000 } ], installment_interest: 0, period_days: 30, accrues_from: due_on.to_s, fine: true, number: number } }
      end)
    end
    MeasureData.analyze("agreements", "agreement_bills", "bills")
    puts "#{count} acordos efetivados criados (#{count / 10} para quebrar, #{count / 10} em atraso)"

    measure.call("tarefa diária dos acordos (quebra e em atraso)", 120) { Agreements::Daily.new(tenant).apply }
    puts "  quebrados: #{Agreement.where(tenant_id: t, state: 'broken').count}; em atraso: #{Agreement.where(tenant_id: t, state: 'active_late').count}; em dia: #{Agreement.where(tenant_id: t, state: 'active_on_time').count}"

    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "341-1234-56789", description: "Conta de medição")
    path = Rails.root.join("tmp", "pagamentos-acordos-#{t}.csv").to_s
    rows = Bill.where(tenant_id: t, kind: "agreement").where("bills.number like '%-02'").joins(:customer).order("bills.id").limit(payments).pluck(:number, "customers.document").map { |number, document| { "number" => number, "document" => document } }
    pay_date = Date.current.strftime("%d/%m/%Y")
    File.open(path, "wb") do |file|
      file.write "canal;identificador;documento;titulo;data_pagamento;valor;meio\n"
      rows.each_with_index { |row, index| file.write [ channel.code, "AG-#{index}", row["document"], row["number"], pay_date, "300,00", "pix" ].join(";") + "\n" }
    end
    import = Portfolio::ImportService.new.start(tenant: tenant, user: user, file: path, mode: :incremental, kind: "payments")
    measure.call("conferência de #{rows.size} pagamentos de parcela pelo número", 120) { import.checker.run(import) }
    puts "  efeito: #{import.reload.summary['effect'].to_json}"
    measure.call("confirmação dos pagamentos de parcela", 120) { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; parcelas pagas: #{Bill.where(tenant_id: t, kind: 'agreement', status: 'paid').count}"

    # Estornos dos pagamentos de parcela (11, R233, etapa 5): os mesmos 20 mil pagamentos estornados pelo arquivo do canal; reabrem a parcela, contam os dias de quebra do estorno
    # (N10) e reavaliam os acordos em lotes.
    reversal_path = Rails.root.join("tmp", "estornos-acordos-#{t}.csv").to_s
    File.open(reversal_path, "wb") do |file|
      file.write "canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo\n"
      rows.size.times { |index| file.write [ channel.code, "AG-#{index}", "EST-#{index}", pay_date, "300,00", "contestação" ].join(";") + "\n" }
    end
    reversal_import = Portfolio::ImportService.new.start(tenant: tenant, user: user, file: reversal_path, mode: :incremental, kind: "reversals")
    measure.call("conferência de #{rows.size} estornos de parcela", 120) { reversal_import.checker.run(reversal_import) }
    measure.call("confirmação dos estornos de parcela", 120) { reversal_import.confirmer.run(reversal_import) }
    puts "  situação: #{reversal_import.reload.status}; parcelas reabertas: #{Bill.where(tenant_id: t, kind: 'agreement', status: 'active').where("jsonb_exists(composition, 'reopened_on')").count}"
    File.delete(reversal_path) if File.exist?(reversal_path)

    # O crédito do contrato na tarefa diária (R232b, N17): 5% dos clientes (os de parcela em atraso) com crédito disponível no contrato; só eles passam pela leitura de títulos.
    MeasureData.insert(Credit, ContractCustomer.joins(:customer).where(customers: { tenant_id: t }).where("customers.id % 20 = 1").pluck(:contract_id).map do |contract_id|
      { tenant_id: t, contract_id: contract_id, kind: "entry", amount_cents: 50_000, reason: "excess", bucket: "available", occurred_at: Time.current - 3.days }
    end)
    measure.call("tarefa diária com crédito em 5% dos contratos (suspende a quebra)", 120) { Agreements::Daily.new(tenant).apply }
    puts "  intervalos congelados abertos: #{Agreement.where(tenant_id: t).where("terms @> ?::jsonb", '{"frozen":[{"kind":"credit","to":null}]}').count}"
    tenant.setting.update!(agreement_policies: { "credit_and_break" => "before_break" })
    measure.call("tarefa diária com crédito em 5% dos contratos (aplica antes de quebrar)", 120) { Agreements::Daily.new(tenant).apply }
    measure.call("resumo da carteira com o cartão de acordos", 30) { Portfolio::Summary.new(user).for_tenant(tenant) }
    measure.call("lista do gestor (casos)", 10) { Agreements::ManagerCases.for(user) }

    # Simulação com 100 títulos (R211, até 1 s).
    big = Customer.create!(tenant: tenant, document: FakeData.cpf(count + 10), name: "Cliente de 100 títulos")
    contract = Contract.create!(tenant: tenant, code: "CT-CEM-TITULOS")
    ContractCustomer.create!(contract: contract, customer: big)
    hundred = (1..100).map { |n| Bill.create!(tenant: tenant, contract: contract, customer: big, number: "H-#{n}", due_date: Date.current - n * 5, amount_cents: 20_000 + n * 100) }
    Charges::Recalculation.new(tenant).apply
    measure.call("simulação de acordo com 100 títulos", 1) { Agreements::Simulation.new(user: user, customer: big, input: Agreements::Simulation::Input.new(bill_ids: hundred.map(&:id), mode: "installments", discounts_bp: Agreements::Caps::COMPONENTS.to_h { |c| [ c, 0 ] }, down_payment_cents: nil, down_payment_on: nil, installments: 6, day: 5, replace: false)).call }
    measure.call("lista de acordos e número do menu", 3) { Agreement.where(tenant_id: t).recent.limit(20).to_a; Agreements::Pending.for(user).count }
    measure.call("arquivo do dia (novidades)", 60) { Agreements::Archive.new(tenant).export!("daily") }

    exit if ENV["KEEP_DATA"] == "1" # só para investigação
    File.delete(path) if File.exist?(path)
    PaymentAllocation.where(payment_id: Payment.where(tenant_id: t).select(:id)).delete_all
    MeasureData.clear(t, %w[abatements reversal_waits credits payment_reversals payments changes task_runs bill_value_versions value_discrepancies bill_valuations agreement_events agreement_exports])
    AgreementSettlement.where(agreement_id: Agreement.where(tenant_id: t).select(:id)).delete_all
    AgreementBill.where(agreement_id: Agreement.where(tenant_id: t).select(:id)).delete_all
    Bill.where(tenant_id: t).delete_all
    Agreement.where(tenant_id: t).delete_all
    MeasureData.wipe_portfolio(t)
    PaymentChannel.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos instrumentos de pagamento (12, parte B): N boletos e Pix emitidos com o fornecedor falso (grava no disco, confere o SHA-256); mede o pedido, a emissão e a leitura: crm:measure_instruments[instrumentos]"
  task :measure_instruments, %i[count] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:count].presence || 2_000).to_i
    tenant = Tenant.provision!("Medição de instrumentos #{Time.current.strftime('%H%M%S')}")
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "MED-#{tenant.id}", description: "Canal de medição", active: true)
    accounts = %w[boleto pix].to_h do |kind|
      account = tenant.payment_accounts.build(channel: channel, modality: kind, provider: "fake", environment: "production", nickname: "Medição #{kind}")
      account.assign_values(config: { "connection_result" => "ok", "pix_key" => "medicao@exemplo.com.br" }, secrets: { "api_key" => "medicao" })
      account.save!
      [ kind, account ]
    end
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format("%-62s %8.3f s", label, elapsed)
      result
    end

    Customer.create!(tenant: tenant, document: "52998224725", name: "Cliente de medição")
    customer = Customer.find_by!(tenant_id: tenant.id)
    issuer = Payments::Issuer.new
    ids = measure.call("pedido de #{count} instrumentos (grava emitting, sem fila)") do
      Array.new(count) { |i| issuer.send(:build, tenant: tenant, kind: i.even? ? "boleto" : "pix", amount_cents: 10_000 + i, customer: customer, due_on: Date.current + 5).id }
    end
    measure.call("emissão de #{count} (fornecedor falso, arquivo em disco, SHA-256 conferido)") do
      PaymentInstrument.where(id: ids).find_each { |instrument| issuer.perform(instrument) }
    end
    puts "ativos: #{PaymentInstrument.where(tenant_id: tenant.id, state: 'active').count}, falhos: #{PaymentInstrument.where(tenant_id: tenant.id, state: 'failed').count}"
    measure.call("leitura de #{count} arquivos pelo leitor (SHA-256 conferido)") do
      PaymentInstrument.where(id: ids).find_each { |instrument| reader = Payments::InstrumentReader.new(instrument); instrument.boleto? ? reader.pdf : reader.qr_png }
    end
    measure.call("limite de taxa: espaçamento de 1.000 jobs a #{Payments::Issuer.per_minute} por minuto") { (0...1000).map { |i| (i * 60.0 / Payments::Issuer.per_minute) }.last }

    exit if ENV["KEEP_DATA"] == "1"
    PaymentInstrument.where(tenant_id: tenant.id).find_each { |instrument| instrument.boleto_pdf.purge; instrument.pix_qr_png.purge }
    PaymentInstrument.where(tenant_id: tenant.id).delete_all
    Change.where(tenant_id: tenant.id).delete_all
    PaymentAccount.where(tenant_id: tenant.id).delete_all
    PaymentChannel.where(tenant_id: tenant.id).delete_all
    Customer.where(tenant_id: tenant.id).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: tenant.id).delete_all
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 da conciliação (12, parte D): N instrumentos Pix ativos ligados a títulos, P% pagos no fornecedor falso; mede a seleção, a conciliação inteira (consulta + baixa pelo caminho do pagamento) e o aviso: crm:measure_reconciliation[instrumentos,percentual_pago]"
  task :measure_reconciliation, %i[count paid_percent] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info # o nível da produção; o registro detalhado de desenvolvimento e teste distorce a vazão

    count = (args[:count].presence || 2_000).to_i
    paid_count = count * (args[:paid_percent].presence || 10).to_i / 100
    tenant = Tenant.provision!("Medição de conciliação #{Time.current.strftime('%H%M%S')}")
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "MED-#{tenant.id}", description: "Canal de medição", active: true)
    account = tenant.payment_accounts.build(channel: channel, modality: "pix", provider: "fake", environment: "production", nickname: "Medição Pix")
    account.assign_values(config: { "connection_result" => "ok", "pix_key" => "medicao@exemplo.com.br" }, secrets: { "api_key" => "medicao" })
    account.save!
    ActiveJob::Base.queue_adapter = :test
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      puts format("%-66s %8.3f s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      result
    end

    measure.call("carteira de #{count} títulos e #{count} instrumentos Pix ativos (lote)") do
      Customer.insert_all!((0...count).map { |i| { tenant_id: tenant.id, document: FakeData.cpf(i), name: FakeData.name(i) } })
      customers = Customer.where(tenant_id: tenant.id).pluck(:document, :id).to_h
      Contract.insert_all!((0...count).map { |i| { tenant_id: tenant.id, code: "CT-#{i}" } })
      contracts = Contract.where(tenant_id: tenant.id).pluck(:code, :id).to_h
      ContractCustomer.insert_all!((0...count).map { |i| { contract_id: contracts["CT-#{i}"], customer_id: customers[FakeData.cpf(i)] } })
      Bill.insert_all!((0...count).map { |i| { tenant_id: tenant.id, contract_id: contracts["CT-#{i}"], customer_id: customers[FakeData.cpf(i)], number: "NF-#{i}", due_date: Date.current - 30, amount_cents: 50_000, status: "active" } })
      bills = Bill.where(tenant_id: tenant.id).pluck(:number, :id).to_h
      PaymentInstrument.insert_all!((0...count).map do |i|
        { tenant_id: tenant.id, account_id: account.id, provider: "fake", customer_id: customers[FakeData.cpf(i)], kind: "pix", state: "active", amount_cents: 50_000, due_on: Date.current + 5,
          external_id: "FAKE-PIX-#{i}", custom_id: format("MED%031d", i), payer_name: FakeData.name(i), payer_document: FakeData.cpf(i), reference_type: "bill", reference_id: bills["NF-#{i}"],
          issued_at: 5.days.ago, created_at: 5.days.ago, updated_at: 5.days.ago }
      end)
      store = Payments::Providers::Fake.store[:instruments]
      (0...count).each { |i| store["FAKE-PIX-#{i}"] = { custom_id: format("MED%031d", i), external_id: "FAKE-PIX-#{i}", status: i < paid_count ? "paid" : "active", kind: "pix", amount_cents: 50_000, due_on: Date.current + 5 } }
    end

    reconciler = Payments::Reconciler.new(tenant)
    measure.call("seleção dos instrumentos a conciliar (índice parcial dos ativos)") { reconciler.due.count }
    measure.call("execução da conciliação (TaskRun e #{count} jobs enfileirados com espaçamento)") { reconciler.call }
    ids = PaymentInstrument.where(tenant_id: tenant.id).order(:id).pluck(:id)
    sync = Payments::InstrumentSync.new
    measure.call("conferência de #{count} instrumentos (consulta ao falso; #{paid_count} pagos baixam o título)") { PaymentInstrument.where(id: ids).find_each { |instrument| sync.call(instrument) } }
    puts "pagamentos: #{Payment.where(tenant_id: tenant.id).count}, instrumentos pagos: #{PaymentInstrument.where(tenant_id: tenant.id, state: 'paid').count}, títulos pagos: #{Bill.where(tenant_id: tenant.id, status: 'paid').count}"
    measure.call("segunda conciliação (nada a fazer: tudo conferido agora)") { reconciler.due.count }
    event = PaymentEvent.record(account, Payments::Providers::Notification.new(event_id: "MED-1", kind: :paid, external_id: "FAKE-PIX-#{count - 1}")).first
    measure.call("aviso: gravar o evento + processar (consulta, ignora)") { Payments::EventProcessor.new.run(event) }

    exit if ENV["KEEP_DATA"] == "1"
    PaymentRow.where(import_id: Import.where(tenant_id: tenant.id).select(:id)).delete_all
    PaymentEvent.where(tenant_id: tenant.id).delete_all
    PaymentInstrument.where(tenant_id: tenant.id).delete_all
    PaymentAllocation.where(payment_id: Payment.where(tenant_id: tenant.id)).delete_all
    [ Abatement, Credit, PaymentReversal, Payment, Change, TaskRun ].each { |model| model.unscoped.where(tenant_id: tenant.id).delete_all }
    Bill.where(tenant_id: tenant.id).delete_all
    ContractCustomer.where(customer_id: Customer.where(tenant_id: tenant.id)).delete_all
    Customer.where(tenant_id: tenant.id).delete_all
    Contract.where(tenant_id: tenant.id).delete_all
    Import.where(tenant_id: tenant.id).destroy_all
    PaymentAccount.where(tenant_id: tenant.id).delete_all
    PaymentChannel.where(tenant_id: tenant.id).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: tenant.id).delete_all
    tenant.destroy
    puts "credor de medição apagado"
  end
end
