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
end
