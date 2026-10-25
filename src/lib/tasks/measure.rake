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
    %w[bill_value_versions reported_surcharges value_discrepancies].each { |table| Portfolio::Sql.run("delete from #{table} where tenant_id = ?", tenant.id) }
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
  desc "V4 de cadastros: carga de N linhas com 3 telefones, 2 e-mails e endereço, duas vezes (a segunda com dados mantidos), ficha com 50 contatos: crm:measure_registry[linhas]"
  task :measure_registry, %i[lines] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    lines = (args[:lines].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de cadastros #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    tenant.update!(phone: "(11) 3000-1000", legal_name: "Credor de medição")
    ActiveJob::Base.queue_adapter = :test
    sql = Portfolio::Sql

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
    sql.run("update customers set name = name || ' Souza', name_kept = true where tenant_id = ? and id % 10 = 0", t)
    sql.run("update customer_contacts set status = 'do_not_disturb', do_not_disturb_on = current_date, kept_by_tenant = true where tenant_id = ? and kind = 'phone' and customer_id % 10 = 0 and key like '11%'", t)
    sql.connection.execute("analyze customers")
    sql.connection.execute("analyze customer_contacts")

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
    measure.call("resumo da carteira") { Portfolio::Summary.new(user).per_tenant }

    [ first, second ].each { |path| File.delete(path) if File.exist?(path) }
    sql.run("delete from import_rows where import_id in (select id from imports where tenant_id = ?)", t)
    sql.run("delete from import_contacts where import_id in (select id from imports where tenant_id = ?)", t)
    %w[bill_value_versions reported_surcharges changes customer_contacts].each { |table| sql.run("delete from #{table} where tenant_id = ?", t) }
    ContractCustomer.where(customer_id: Customer.where(tenant_id: t)).delete_all
    [ Bill, Customer, Contract ].each { |model| model.where(tenant_id: t).delete_all }
    Import.where(tenant_id: t).destroy_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos direitos do titular (07): N clientes com título pago há 6 anos, contatos, acionamentos e pagamentos; mede exportar, anonimizar um, previsão e a tarefa diária: crm:measure_titular[clientes]"
  task :measure_titular, %i[customers] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    count = (args[:customers].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de direitos do titular #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    sql = Portfolio::Sql
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Um cliente por linha, um contrato por cliente, um título pago há 6 anos com o pagamento, 3 contatos, 1 acionamento com texto e histórico.
    sql.run("insert into customers (tenant_id, document, name, created_at, updated_at) select ?, lpad(i::text, 11, '0'), 'Cliente ' || i, now(), now() from generate_series(1, ?) i", t, count)
    sql.run("insert into contracts (tenant_id, code, created_at, updated_at) select ?, 'CT-' || id, now(), now() from customers where tenant_id = ?", t, t)
    sql.execute("analyze customers, contracts")
    sql.run("insert into contract_customers (contract_id, customer_id, roles) select k.id, c.id, '[]'::jsonb from customers c join contracts k on k.tenant_id = c.tenant_id and k.code = 'CT-' || c.id where c.tenant_id = ?", t)
    sql.run("insert into bills (tenant_id, contract_id, customer_id, number, due_date, amount_cents, paid_cents, paid_on, description, status, created_at, updated_at) " \
            "select ?, cc.contract_id, c.id, 'NF-' || c.id, current_date - 2300, 10000, 10000, current_date - 2200, 'Mensalidade de ' || c.name, 'paid', now(), now() " \
            "from customers c join contract_customers cc on cc.customer_id = c.id where c.tenant_id = ?", t, t)
    channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "MEDICAO", description: "Canal de medição")
    sql.run("insert into payments (tenant_id, channel_id, identifier, document, bill_number, bill_id, paid_on, amount_cents, payment_method, status, applied_cents, created_at, updated_at) " \
            "select ?, ?, 'P-' || b.id, c.document, b.number, b.id, current_date - 2200, 10000, 'pix', 'applied', 10000, now(), now() from bills b join customers c on c.id = b.customer_id where b.tenant_id = ?", t, channel.id, t)
    sql.run("insert into customer_contacts (tenant_id, customer_id, kind, key, value, origin, status, created_at, updated_at) " \
            "select ?, c.id, k.kind, k.kind || c.id, 'contato ' || k.kind || ' ' || c.id, 'load', 'valid', now(), now() from customers c cross join (values ('phone'), ('email'), ('address')) k(kind) where c.tenant_id = ?", t, t)
    result = ContactResult.where(tenant_id: t).first
    sql.run("insert into contact_attempts (tenant_id, customer_id, result_id, result_kind, channel, contact_used, text, contacted_at, created_at, updated_at) " \
            "select ?, id, ?, ?, 'phone', 'contato phone ' || id, 'Falou com ' || name, now() - interval '2200 days', now(), now() from customers where tenant_id = ?", t, result.id, result.kind, t)
    sql.run("insert into changes (tenant_id, subject_type, subject_id, event, field, before, after, occurred_at) select ?, 'customer', id, 'updated', 'name', 'Antigo ' || name, name, now() from customers where tenant_id = ?", t, t)
    sql.execute("analyze customers, bills, payments, contracts, contract_customers, contact_attempts, customer_contacts, changes")
    puts "#{count} clientes criados no credor de medição"

    # Exportação e anonimização de um cliente com 1.000 acionamentos (limites da especificação: 3 s e 5 s).
    heavy = Customer.where(tenant_id: t).order(:id).first
    sql.run("insert into contact_attempts (tenant_id, customer_id, result_id, result_kind, channel, contact_used, text, contacted_at, created_at, updated_at) " \
            "select ?, ?, ?, ?, 'phone', 'contato phone', 'Texto do acionamento ' || i, now() - interval '2200 days' + i * interval '1 minute', now(), now() from generate_series(1, 1000) i", t, heavy.id, result.id, result.kind)
    measure.call("exportar um cliente com 1.000 acionamentos", 3) { Titular::Exporter.new(heavy).to_h }
    measure.call("anonimizar um cliente com 1.000 acionamentos (a pedido)", 5) { Titular::Anonymizer.on_request(heavy, actor: user, reason: "medição", document: heavy.document) }

    due = measure.call("previsão de 30 dias e vencidos (consulta de conjunto)") { Titular::Retention.due([ t ], within: 30).count }
    puts "  vencidos ou previstos: #{due}"
    measure.call("página de guarda: primeira página da previsão (20)") { Pagination.new(Titular::Retention.due([ t ], within: 30).order("due_on, id"), page: 1, per_page: 20).records.to_a }
    run = measure.call("tarefa diária: anonimiza #{count - 1} clientes vencidos", 600) { Titular::RetentionRun.new(tenant).call }
    puts "  execução: #{run.status}, #{run.processed} anonimizados, #{run.failed} falhas"
    puts "  clientes ainda identificados: #{Customer.where(tenant_id: t, anonymized_at: nil).count}"
    puts "  dado pessoal restante nos acionamentos: #{ContactAttempt.where(tenant_id: t).where("text like 'Falou com%' or text like 'Texto do%'").count}"

    %w[bill_value_versions changes customer_contacts contact_attempts payments task_runs].each { |table| sql.run("delete from #{table} where tenant_id = ?", t) }
    ContractCustomer.where(customer_id: Customer.where(tenant_id: t)).delete_all
    [ Bill, Customer, Contract, PaymentChannel ].each { |model| model.where(tenant_id: t).delete_all }
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos segmentos (08): N contratos (1 cliente e 2 títulos cada) e 5 segmentos; mede conferência, confirmação, recálculo diário, aba, lista e ficha: crm:measure_segments[contratos]"
  task :measure_segments, %i[contracts] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    count = (args[:contracts].presence || 10_000).to_i
    tenant = Tenant.provision!("Medição de segmentos #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    sql = Portfolio::Sql
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      peak = (File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i / 1024 rescue 0)
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-62s %8.2f s   (pico de memória %d MB)%s", label, elapsed, peak, verdict)
      result
    end

    # Um cliente por contrato (60% CPF, 40% CNPJ), dois títulos de produtos diferentes, atrasos de 1 a 400 dias.
    sql.run("insert into customers (tenant_id, document, name, created_at, updated_at) select ?, case when i % 5 < 3 then lpad(i::text, 11, '0') else lpad(i::text, 14, '0') end, 'Cliente ' || i, now(), now() from generate_series(1, ?) i", t, count)
    sql.run("insert into contracts (tenant_id, code, created_at, updated_at) select ?, 'CT-' || id, now() - ((id % 700) || ' days')::interval, now() from customers where tenant_id = ?", t, t)
    sql.execute("analyze customers, contracts")
    sql.run("insert into contract_customers (contract_id, customer_id, roles) select k.id, c.id, '[]'::jsonb from customers c join contracts k on k.tenant_id = c.tenant_id and k.code = 'CT-' || c.id where c.tenant_id = ?", t)
    sql.run("insert into bills (tenant_id, contract_id, customer_id, number, due_date, amount_cents, paid_cents, status, product, created_at, updated_at) " \
            "select ?, cc.contract_id, c.id, 'NF-' || c.id || '/' || n, current_date - ((1 + (c.id * 37 + n * 11) % 400)::int), 5000 + (c.id * 7919 + n * 131) % 250000, 0, 'active', " \
            "case n when 1 then 'Mensalidade' else 'Cartão' end, now(), now() " \
            "from customers c join contract_customers cc on cc.customer_id = c.id cross join generate_series(1, 2) n where c.tenant_id = ?", t, t)
    sql.execute("analyze bills, contract_customers")
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
    sql.execute("analyze contract_segments, contracts")
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
    sql.run("delete from changes where tenant_id = ?", t)
    sql.run("delete from task_runs where tenant_id = ?", t)
    ContractCustomer.where(customer_id: Customer.where(tenant_id: t)).delete_all
    [ Bill, Customer, Contract ].each { |model| model.where(tenant_id: t).delete_all }
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    puts "credor de medição apagado"
  end

  desc "V4 dos encargos (09): N contratos (2 títulos vencidos cada), 5 segmentos com regras diferentes, índices desde 2000 e P pagamentos; mede recálculo, conferência, confirmação, lista, ficha, resumo e a baixa por componente: crm:measure_charges[contratos,pagamentos]"
  task :measure_charges, %i[contracts payments] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    count = (args[:contracts].presence || 10_000).to_i
    payments = (args[:payments].presence || count).to_i
    tenant = Tenant.provision!("Medição de encargos #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    user = User.create!(name: "Medição", email_address: "medicao#{t}@exemplo.com.br", password: SecureRandom.base58(24))
    Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: "Gestor"))
    ActiveJob::Base.queue_adapter = :test
    sql = Portfolio::Sql
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

    (1..count).each_slice(10_000) { |slice| Customer.insert_all!(slice.map { |i| { tenant_id: t, document: FakeData.cpf(i), name: "Cliente #{i}" } }) }
    sql.run("insert into contracts (tenant_id, code, created_at, updated_at) select ?, 'CT-' || id, now() - ((id % 700) || ' days')::interval, now() from customers where tenant_id = ?", t, t)
    sql.execute("analyze customers, contracts")
    sql.run("insert into contract_customers (contract_id, customer_id, roles) select k.id, c.id, '[]'::jsonb from customers c join contracts k on k.tenant_id = c.tenant_id and k.code = 'CT-' || c.id where c.tenant_id = ?", t)
    sql.run("insert into bills (tenant_id, contract_id, customer_id, number, due_date, amount_cents, paid_cents, status, product, created_at, updated_at) " \
            "select ?, cc.contract_id, c.id, 'NF-' || c.id || '/' || n, current_date - ((1 + (c.id * 37 + n * 11) % 400)::int), 5000 + (c.id * 7919 + n * 131) % 250000, 0, 'active', " \
            "case n when 1 then 'Mensalidade' else 'Cartão' end, now(), now() " \
            "from customers c join contract_customers cc on cc.customer_id = c.id cross join generate_series(1, 2) n where c.tenant_id = ?", t, t)
    sql.execute("analyze bills, contract_customers")
    puts "#{count} contratos (#{count * 2} títulos vencidos) criados no credor de medição"

    tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, charge_index: "ipca")
    Segment.catch_all_of(tenant).update!(interest_kind: "fixed", fees_pct: 10, fees_in_contract: true)
    Segment.create!(tenant: tenant, name: "Varejo PF recente", position: 1, person_type: "person", min_overdue_days: 1, max_overdue_days: 90, interest_kind: "fixed", index_code: "ipca")
    Segment.create!(tenant: tenant, name: "PF", position: 2, person_type: "person", interest_kind: "fixed", interest_pct: 2, index_code: "inpc")
    Segment.create!(tenant: tenant, name: "Pessoa jurídica", position: 3, person_type: "company", interest_kind: "legal", index_code: "ipca")
    Segment.create!(tenant: tenant, name: "Muito vencido", position: 4, min_overdue_bills: 2, min_overdue_percent: 50, interest_kind: "fixed", interest_form: "compound", index_code: "igpm")
    Charges::RuleHistory.record!(tenant, since: Date.current - 400)
    Segments::Recalculation.new(tenant).apply
    sql.execute("analyze contract_segments, contracts")

    measure.call("recálculo diário do valor atualizado (#{count * 2} títulos)", 120) { Charges::Recalculation.new(tenant).apply }
    puts "  títulos com valor atualizado: #{BillValuation.where(tenant_id: t).count}; total R$ #{Money.format(BillValuation.where(tenant_id: t).sum(:total_cents))}"
    sql.execute("analyze bill_valuations")

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
    measure.call("resumo com atualizado, faixas e segmentos", 10) { Portfolio::Summary.new(user).per_tenant }
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
      file.write "canal;identificador;documento;titulo;data_pagamento;valor;meio\n"
      valuations.each_with_index do |(bill_id, total, principal), index|
        value = case index % 20 when 0..11 then total when 12..16 then total / 2 else principal end
        number, customer = numbers.fetch(bill_id)
        file.write [ channel.code, "ID-#{index}", documents.fetch(customer), number, (Date.current - 1).strftime("%d/%m/%Y"), Money.format(value), "pix" ].join(";") + "\n"
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
    sql.run("delete from payment_rows where import_id in (?)", Import.where(tenant_id: t).pluck(:id).presence || [ 0 ])
    sql.run("delete from payment_allocations where bill_id in (select id from bills where tenant_id = ?)", t)
    sql.run("delete from bill_valuations where tenant_id = ?", t)
    %w[credits payment_reversals payments changes task_runs bill_value_versions value_discrepancies].each { |table| sql.run("delete from #{table} where tenant_id = ?", t) }
    ContractCustomer.where(customer_id: Customer.where(tenant_id: t)).delete_all
    [ Bill, Customer ].each { |model| model.where(tenant_id: t).delete_all }
    sql.run("delete from contract_segments where contract_id in (select id from contracts where tenant_id = ?)", t)
    Contract.where(tenant_id: t).delete_all
    sql.run("delete from charge_rule_versions where segment_id in (select id from segments where tenant_id = ?)", t)
    Import.where(tenant_id: t).destroy_all
    PaymentChannel.where(tenant_id: t).delete_all
    tenant.contact_results.delete_all
    Membership.where(tenant_id: t).delete_all
    user.destroy
    tenant.destroy
    IndexRate.delete_all
    IndexRate.insert_all!(saved_rates.map { |row| row.except("id") }) if saved_rates.any?
    puts "credor de medição apagado"
  end
end
