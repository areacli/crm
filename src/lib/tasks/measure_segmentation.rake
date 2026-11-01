# Medição da linguagem dos segmentos (13; decisão 0023, M1 a M4), só do desenho novo. Nada disto roda em produção.
require_relative "../measure_data"

namespace :crm do
  desc "M1 a M4 da segmentação: N contratos com títulos, acionamentos, contatos, promessas, acordos e pagamentos; crm:measure_segmentation[contratos]"
  task :measure_segmentation, %i[contracts] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info
    count = (args[:contracts].presence || 10_000).to_i
    # TENANT=<id> reaproveita a massa de um credor mantido com KEEP=1 (para medir de novo sem recriar).
    reuse = ENV["TENANT"].presence
    tenant = reuse ? Tenant.find(reuse) : Tenant.provision!("Medição da segmentação #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    now = Time.current
    measure = lambda do |label, limit = nil, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      verdict = limit ? (elapsed <= limit ? "  ok (limite #{limit} s)" : "  ACIMA do limite de #{limit} s") : ""
      puts format("%-70s %8.2f s%s", label, elapsed, verdict)
      result
    end
    # WORK_MEM=64MB mede com a memória de ordenação e agrupamento da consulta aumentada só na transação (SET LOCAL).
    run = lambda do |query|
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("set local work_mem = '#{ENV['WORK_MEM']}'") if ENV["WORK_MEM"].present?
        ActiveRecord::Base.connection.select_all(query.sql, "Segments", query.binds).to_a
      end
    end

    unless reuse
      # Carteira: um cliente por contrato (60% CPF), três títulos com produtos e vencimentos variados (um a vencer em parte deles); um terço dos
      # clientes é titular também do contrato seguinte, para "outros contratos do titular".
      measure.call("massa: #{count} contratos, #{count * 3} títulos") do
        MeasureData.portfolio(t, count, document: ->(i) { i % 5 < 3 ? i.to_s.rjust(11, "0") : i.to_s.rjust(14, "0") }, contract_age: ->(i) { i % 900 },
                              bills_per: 3, bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - ((i * 37 + n * 11) % 500) + 60, amount_cents: 5000 + (i * 7919 + n * 131) % 250_000,
                                                               product: %w[Mensalidade Cartão Empréstimo][(i + n) % 3] } })
      end
      contracts = Contract.where(tenant_id: t).order(:id).pluck(:id)
      links = ContractCustomer.where(contract_id: contracts).pluck(:contract_id, :customer_id).to_h
      extra = contracts.each_slice(3).filter_map { |a, b, _| b && { contract_id: b, customer_id: links.fetch(a), roles: [] } }
      MeasureData.insert(ContractCustomer, extra)
      results = ContactResult.where(tenant_id: t).pluck(:id, :kind)
      channel = PaymentChannel.insert_all!([ { tenant_id: t, kind: "bank", code: "MED", description: "Medição", created_at: now, updated_at: now } ], returning: %w[id]).rows.flatten.first

      measure.call("massa: acionamentos, contatos, promessas, acordos e pagamentos") do
        attempts = contracts.each_with_index.flat_map do |id, i|
          (0...(i % 4)).map { |n| result_id, kind = results[(i + n) % results.size]; { tenant_id: t, customer_id: links.fetch(id), contract_id: id, result_id: result_id, result_kind: kind, channel: "phone", contacted_at: now - ((i * 13 + n * 29) % 240).days, created_at: now, updated_at: now } }
        end
        MeasureData.insert(ContactAttempt, attempts)
        MeasureData.insert(CustomerContact, links.values.each_with_index.flat_map do |customer, i|
          (0...(i % 3)).map { |n| { tenant_id: t, customer_id: customer, kind: n.zero? ? "phone" : "address", key: "k#{i}-#{n}", value: "x", origin: "load", status: (i + n) % 4 == 0 ? "invalid" : "valid",
                                     city: n.zero? ? nil : %w[São\ Paulo Campinas Recife][i % 3], state: n.zero? ? nil : %w[SP SP PE][i % 3], created_at: now, updated_at: now } }
        end)
        attempt_ids = ContactAttempt.where(tenant_id: t).order(:id).pluck(:id, :contract_id, :customer_id)
        MeasureData.insert(PaymentPromise, attempt_ids.each_with_index.filter_map do |(attempt, contract, customer), i|
          next unless i % 5 == 0

          { tenant_id: t, customer_id: customer, contract_id: contract, contact_attempt_id: attempt, state: PaymentPromise::STATES[i % PaymentPromise::STATES.size], payment_method: "pix",
            promised_on: Date.current, contacted_on: Date.current, total_cents: 10_000, created_at: now - (i % 300).days, updated_at: now }
        end)
        agreements = contracts.each_with_index.filter_map do |id, i|
          next unless i % 7 == 0

          { tenant_id: t, customer_id: links.fetch(id), number: "ACD-M#{i}", state: Agreement::STATES[i % Agreement::STATES.size], mode: "installments", built_on: Date.current, valid_until: Date.current,
            base_cents: 1, discount_cents: 0, value_cents: 1, net_cents: 1, down_payment_cents: 1, down_payment_due: Date.current, total_cents: 1, effectuated_at: now - (i % 200).days, created_at: now, updated_at: now }
        end
        MeasureData.insert(Agreement, agreements)
        bills = Bill.where(tenant_id: t).pluck(:contract_id, :id).group_by(&:first).transform_values { |rows| rows.map(&:last) }
        numbers = Agreement.where(tenant_id: t).pluck(:number, :id).to_h
        MeasureData.insert(AgreementBill, agreements.map do |row|
          contract = contracts[row[:number].delete_prefix("ACD-M").to_i]
          { agreement_id: numbers.fetch(row[:number]), bill_id: bills.fetch(contract).first, contract_id: contract, value_cents: 1, amount_cents: 1, paid_cents: 0, held: false }
        end)
        MeasureData.insert(Payment, contracts.each_with_index.filter_map do |id, i|
          next unless i % 3 == 0

          { tenant_id: t, channel_id: channel, identifier: "P#{i}", document: "0", bill_number: "x", bill_id: bills.fetch(id).last, paid_on: Date.current - (i % 120), amount_cents: 1000 + i % 9000,
            payment_method: %w[pix boleto transfer][i % 3], status: "applied", created_at: now, updated_at: now }
        end)
      end
    end
    MeasureData.analyze("customers", "contracts", "bills", "contract_customers", "contact_attempts", "customer_contacts", "payment_promises", "agreements", "agreement_bills", "payments")
    contracts = Contract.where(tenant_id: t).order(:id).pluck(:id)
    results = ContactResult.where(tenant_id: t).pluck(:id, :kind)

    expr = ->(subject, nodes) { Segments::Expression.new("grammar" => 1, "subject" => subject, "all" => nodes) }
    promised = results.first.first
    # Pior caso (M1): 20 condições por segmento, por todas as coleções, janelas e "outros contratos do titular"; os valores variam por item.
    heavy = lambda do |k|
      [
        { "path" => "overdue_days", "op" => "between", "value" => [ k, 400 + k ] },
        { "path" => "balance", "op" => "gte", "value" => 1000 * k },
        { "path" => "overdue_percent", "op" => "lte", "value" => 100 - (k % 5) },
        { "path" => "person_type", "op" => "in", "value" => %w[person company] },
        { "path" => "product", "op" => "ne", "value" => "Produto #{k}" },
        { "path" => "product_largest", "op" => "ne", "value" => "Outro #{k}" },
        { "any" => [ { "path" => "broke_agreement", "op" => "is", "negate" => true }, { "path" => "in_arrears", "op" => "is" } ] },
        { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => k % 2 },
        { "path" => "bills", "aggregate" => "sum", "field" => "balance", "op" => "gte", "value" => k },
        { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "in", "value" => [ "Mensalidade", "Cartão", "Empréstimo" ] } },
        { "path" => "bills", "quantifier" => "all", "where" => { "field" => "amount", "op" => "gte", "value" => k } },
        { "path" => "contact_attempts", "quantifier" => "none", "where" => { "field" => "result", "op" => "eq", "value" => promised }, "within_days" => 1 + k },
        { "path" => "contact_attempts", "aggregate" => "count", "op" => "lte", "value" => 50 + k, "within_days" => 90 },
        { "path" => "contacts", "qualifier" => "invalid", "aggregate" => "count", "op" => "lte", "value" => 5 + k },
        { "path" => "promises", "quantifier" => "none", "where" => { "field" => "state", "op" => "eq", "value" => "canceled" }, "within_days" => 10 + k },
        { "path" => "agreements", "quantifier" => "none", "where" => { "field" => "state", "op" => "eq", "value" => "expired" } },
        { "path" => "payments", "aggregate" => "sum", "field" => "amount", "op" => "lte", "value" => 10_000_000 + k, "within_days" => 120 },
        { "path" => "holder.person_type", "op" => "in", "value" => %w[person company] },
        { "path" => "holder.other_contracts", "aggregate" => "count", "op" => "lte", "value" => 10 + k }
      ]
    end
    entries = (1..30).map { |k| [ 1_000 + k, expr.call("contracts", heavy.call(k)).tap { |e| raise e.errors.inspect unless e.valid? } ] }
    compiler = Segments::Compiler.new(tenant)

    puts "Base: #{count} contratos; #{Bill.where(tenant_id: t).count} títulos; #{ContactAttempt.where(tenant_id: t).count} acionamentos; #{CustomerContact.where(tenant_id: t).count} contatos; " \
         "#{PaymentPromise.where(tenant_id: t).count} promessas; #{Agreement.where(tenant_id: t).count} acordos; #{Payment.where(tenant_id: t).count} pagamentos"
    query = compiler.classify(entries, default_id: 1)
    puts "M1: consulta do enquadramento com 30 itens de 20 condições: #{query.sql.size} caracteres, #{query.binds.size} parâmetros"
    rows = measure.call("M1 enquadramento (pior caso): cálculo de todos os contratos", 10) { run.call(Segments::Compiler.new(tenant).classify(entries, default_id: 1)) }
    puts "  #{rows.size} contratos enquadrados; por item: #{rows.group_by { |row| row['tier_id'] }.transform_values(&:size).sort.first(6).to_h}"
    simple = [ [ 2, expr.call("contracts", [ { "path" => "product", "op" => "eq", "value" => "Mensalidade" }, { "path" => "overdue_days", "op" => "lte", "value" => 90 } ]) ],
               [ 3, expr.call("contracts", [ { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "eq", "value" => "Cartão" } } ]) ],
               [ 4, expr.call("contracts", [ { "path" => "person_type", "op" => "eq", "value" => "company" } ]) ] ]
    measure.call("M1 enquadramento da demonstração (3 itens simples)", 10) { run.call(Segments::Compiler.new(tenant).classify(simple, default_id: 1)) }

    heaviest = entries.last.last
    measure.call("M2 conferir o segmento mais pesado (total e cada condição)", 10) { run.call(Segments::Compiler.new(tenant).probe(heaviest)) }

    examples = {
      "contratos com atraso longo" => expr.call("contracts", [ { "path" => "overdue_days", "op" => "gt", "value" => 90 } ]),
      "clientes sem contato válido" => expr.call("customers", [ { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" } ]),
      "contratos com promessa quebrada recente" => expr.call("contracts", [ { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" }, "within_days" => 90 } ]),
      "contratos sem acionamento em 30 dias" => expr.call("contracts", [ { "path" => "contact_attempts", "quantifier" => "none", "within_days" => 30 } ]),
      "clientes PF com atraso > 90 e acionamento recente" => expr.call("customers", [ { "path" => "person_type", "op" => "eq", "value" => "person" }, { "path" => "overdue_days", "op" => "gt", "value" => 90 },
                                                                                   { "path" => "contact_attempts", "aggregate" => "count", "op" => "gte", "value" => 1, "within_days" => 60 } ]),
      "o mais pesado (20 condições)" => heaviest
    }
    examples.each do |label, expression|
      raise expression.errors.inspect unless expression.valid?

      found = measure.call("M3 filtro da lista: #{label}", 2) do
        matching = Segments::Compiler.new(tenant).matching(expression)
        sql = expression.subject == "customers" ? "select count(*) as n from (#{matching.sql}) m" : "select count(distinct cc.customer_id) as n from contract_customers cc join (#{matching.sql}) m on m.id = cc.contract_id"
        run.call(Segments::Compiler::Query.new(sql, matching.binds)).first["n"]
      end
      puts "  #{found} clientes"
    end

    if ENV["EXPLAIN"] == "1"
      { "simples" => Segments::Compiler.new(tenant).classify(simple, default_id: 1), "pesado" => Segments::Compiler.new(tenant).probe(heaviest) }.each do |label, plan_query|
        plan = run.call(Segments::Compiler::Query.new("explain (analyze, buffers, format text) #{plan_query.sql}", plan_query.binds)).map(&:values).flatten
        File.write(Rails.root.join("tmp", "explain-segmentacao-#{label}.txt"), plan.join("\n"))
        puts "plano #{label}: tmp/explain-segmentacao-#{label}.txt"
      end
    end

    if ENV["KEEP"] == "1"
      puts "KEEP=1: credor de medição #{t} mantido"
      next
    end
    MeasureData.clear(t, %w[payments payment_promises contact_attempts customer_contacts changes task_runs])
    AgreementBill.where(contract_id: contracts).delete_all
    MeasureData.clear(t, %w[agreements payment_channels])
    MeasureData.wipe_portfolio(t)
    Membership.where(tenant_id: t).delete_all
    tenant.destroy
    puts "credor de medição apagado"
  end
end
