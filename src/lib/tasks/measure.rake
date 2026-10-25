# Medições com volume (V4) e planilhas fictícias. Nada disto roda em produção.
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

  desc "V4: importa uma carteira fictícia e mede conferência, confirmação, lista e resumo: crm:measure_import[linhas,títulos_por_cliente]"
  task :measure_import, %i[lines per_customer] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

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
    measure.call("conferência de #{lines} linhas") { Portfolio::ImportChecker.new.run(import) }
    import.reload
    puts "  resumo: #{import.summary.slice('valid', 'rejected', 'customers').to_json}"
    measure.call("confirmação de #{lines} linhas") { Portfolio::ImportConfirmer.new.run(import) }
    puts "  situação: #{import.reload.status}"

    query = Portfolio::Query.new(user)
    measure.call("lista de clientes (primeira página)") { query.customers.limit(20).to_a }
    measure.call("lista de clientes (contagem total)") { query.customers.except(:select, :order).count }
    measure.call("lista de clientes (busca por nome)") { query.customers(search: "silva").limit(20).to_a }
    measure.call("resumo da carteira") { Portfolio::Summary.new(user).per_tenant }

    File.delete(path) if File.exist?(path)
    Portfolio::Sql.run("delete from import_rows where import_id = ?", import.id)
    [ Bill, Change, ContractCustomer ].each { |model| model.where(tenant_id: tenant.id).delete_all if model.column_names.include?("tenant_id") }
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

    # Carteira: um cliente, um contrato e um título por pagamento previsto (valor conhecido, para os perfis abaixo).
    measure.call("carteira de #{count} títulos (inserção em lote)") do
      (0...count).each_slice(10_000) do |slice|
        Customer.insert_all!(slice.map { |index| { tenant_id: tenant.id, document: FakeData.cpf(index), name: FakeData.name(index) } })
        ids = Customer.where(tenant_id: tenant.id, document: slice.map { |index| FakeData.cpf(index) }).pluck(:document, :id).to_h
        Contract.insert_all!(slice.map { |index| { tenant_id: tenant.id, code: "CT-#{index}" } })
        contracts = Contract.where(tenant_id: tenant.id, code: slice.map { |index| "CT-#{index}" }).pluck(:code, :id).to_h
        ContractCustomer.insert_all!(slice.map { |index| { contract_id: contracts.fetch("CT-#{index}"), customer_id: ids.fetch(FakeData.cpf(index)) } })
        Bill.insert_all!(slice.map do |index|
          { tenant_id: tenant.id, contract_id: contracts.fetch("CT-#{index}"), customer_id: ids.fetch(FakeData.cpf(index)), number: "NF-#{index}",
            due_date: Date.current - 30, amount_cents: 10_000 + ((index * 7919) % 200_000) }
        end)
      end
    end
    Portfolio::Sql.connection.execute("analyze bills")
    Portfolio::Sql.connection.execute("analyze customers")

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
    measure.call("conferência de #{count} pagamentos") { import.checker.run(import) }
    puts "  resumo: #{import.reload.summary.slice('valid', 'rejected').to_json} efeito: #{import.summary['effect'].to_json}"
    measure.call("confirmação de #{count} pagamentos") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}"
    measure.call("resumo da carteira com recebimentos") { Portfolio::Summary.new(user).per_tenant }

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
    measure.call("conferência de #{reversal_count} estornos") { reversal.checker.run(reversal) }
    puts "  resumo: #{reversal.reload.summary.slice('valid', 'rejected').to_json} efeito: #{reversal.summary['effect'].to_json}"
    measure.call("confirmação de #{reversal_count} estornos") { reversal.confirmer.run(reversal) }
    puts "  situação: #{reversal.reload.status}"
    measure.call("resumo da carteira depois dos estornos") { Portfolio::Summary.new(user).per_tenant }

    [ payments_path, reversals_path ].each { |path| File.delete(path) if File.exist?(path) }
    Portfolio::Sql.run("delete from payment_rows where import_id in (?)", Import.where(tenant_id: tenant.id).pluck(:id))
    [ Credit, PaymentReversal, Payment, Change ].each { |model| model.unscoped.where(tenant_id: tenant.id).delete_all }
    Bill.where(tenant_id: tenant.id).delete_all
    ContractCustomer.where(customer_id: Customer.where(tenant_id: tenant.id)).delete_all
    Customer.where(tenant_id: tenant.id).delete_all
    Contract.where(tenant_id: tenant.id).delete_all
    Import.where(tenant_id: tenant.id).destroy_all
    PaymentChannel.where(tenant_id: tenant.id).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end
  desc "V4 de acionamentos: gera N acionamentos num credor de medição e mede ficha, lista, resumo e registro: crm:measure_contacts[acionamentos]"
  task :measure_contacts, %i[attempts] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    count = (args[:attempts].presence || 1_000_000).to_i
    tenant = Tenant.provision!("Medição de acionamentos #{Time.current.strftime('%H%M%S')}")
    user = User.create!(name: "Medição", email_address: "medicao#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    operators = [ user.id ] + 4.times.map { |i| User.create!(name: "Operador #{i}", email_address: "op#{i}-#{tenant.id}@exemplo.com.br", password: SecureRandom.base58(24)).id }
    connection = Portfolio::Sql
    t = tenant.id

    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format("%-62s %8.3f s", label, elapsed)
      result
    end

    # 20 mil clientes e N acionamentos espalhados pelos últimos 92 dias, nos 11 resultados, em 5 operadores e 5 canais.
    connection.execute("insert into customers (tenant_id, document, name, created_at, updated_at) select #{t}, lpad(g::text, 11, '0'), 'Cliente ' || g, now(), now() from generate_series(1, 20000) g")
    first_customer = Customer.where(tenant_id: t).minimum(:id)
    results = tenant.contact_results.ordered.to_a
    result_case = "case (g % 11) #{results.each_with_index.map { |result, i| "when #{i} then #{result.id}" }.join(' ')} end"
    kind_case = "case (g % 11) #{results.each_with_index.map { |result, i| "when #{i} then '#{result.kind}'" }.join(' ')} end"
    measure.call("gerar #{count} acionamentos (com os 3 índices)") do
      connection.execute(<<~SQL)
        insert into contact_attempts (tenant_id, customer_id, user_id, result_id, result_kind, channel, text, contacted_at, created_at, updated_at)
        select #{t}, #{first_customer} + case when g <= 1000 then 0 else g % 20000 end, (array[#{operators.join(',')}])[1 + g % 5], #{result_case}, #{kind_case},
               (array['phone','whatsapp','sms','email','letter'])[1 + g % 5], 'Texto de medição ' || g,
               now() - ((g % 92) || ' days')::interval - ((g % 86400) || ' seconds')::interval,
               now(), now()
        from generate_series(1, #{count}) g
      SQL
    end
    # Os 1.000 primeiros acionamentos são do primeiro cliente (a ficha pesada).
    heavy = Customer.where(tenant_id: t).order(:id).first
    connection.execute("analyze contact_attempts")

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
    measure.call("resumo da carteira (inclui os acionamentos de 7 e 30 dias)") { Portfolio::Summary.new(user).per_tenant }
    measure.call("registrar um acionamento (regras, gravação e histórico)") do
      Contacts::Recorder.new(user).record(heavy, channel: "phone", result_id: results.last.id, text: "medição do registro")
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

    lines = (args[:lines].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de divergências #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test
    sql = Portfolio::Sql

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
    sql.run("update bills set paid_cents = amount_cents / 3 where tenant_id = ? and number like '%/1' and split_part(substring(number from 4), '/', 1)::int % 5 = 0", t)
    sql.connection.execute("analyze bills")

    import = service.start(tenant: tenant, user: user, file: second, mode: :incremental)
    measure.call("2ª carga: conferência (10% com pagamento e valor novo)") { import.checker.run(import) }
    puts "  divergências: #{import.reload.summary['discrepancies']['count']}"
    measure.call("2ª carga: confirmação") { import.confirmer.run(import) }
    puts "  situação: #{import.reload.status}; divergências abertas: #{ValueDiscrepancy.where(tenant_id: t, status: 'open').count}; versões: #{BillValueVersion.where(tenant_id: t).count}"

    measure.call("resumo da carteira (crédito, excedente e recuperado)") { Portfolio::Summary.new(user).per_tenant }
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
    %w[value_discrepancies reported_surcharges bill_value_versions changes].each { |table| sql.run("delete from #{table} where tenant_id = ?", t) }
    sql.run("delete from import_rows where import_id in (select id from imports where tenant_id = ?)", t)
    ContractCustomer.where(customer_id: Customer.where(tenant_id: t)).delete_all
    [ Bill, Customer, Contract ].each { |model| model.where(tenant_id: t).delete_all }
    Import.where(tenant_id: t).destroy_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end
end
