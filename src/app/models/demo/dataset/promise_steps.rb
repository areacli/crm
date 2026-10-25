module Demo
  class Dataset
    # Promessas de pagamento nos oito estados (10): registradas pelo acionamento, na data em que teriam sido (o relógio viaja), pagas pelo número `PRM-` e
    # fechadas pela tarefa diária.
    module PromiseSteps
      private
        def promises(tenant)
          PromiseLimit.where(profile_id: tenant.profiles.find_by!(name: "Operador").id).update_all(max_days: 10)
          result = ContactResult.find_by!(tenant_id: tenant.id, name: "Prometeu pagar")
          fresh = candidates(tenant, 40, older_than: 50)
          old = candidates(tenant, 10, older_than: 60)
          make = lambda do |ago, ahead, method: "pix", pool: fresh|
            first_that_works(pool) do |source|
              customer, contract, bills = source.values_at(:customer, :contract, :bills)
              travel_to((today - ago).in_time_zone.change(hour: 11)) do
                attempt = Contacts::Recorder.new(@operator).record(customer, { channel: "phone", result_id: result.id, contract_id: contract.id, promise_contract_id: contract.id,
                                                                               promise_bill_ids: bills.first(2).map { |bill| bill.id.to_s }, promise_payment_method: method,
                                                                               promise_on: (today - ago + ahead).iso8601, text: "Prometeu pagar no prazo." })
                attempt.promise or raise Promises::Refused, "sem promessa"
              end
            end
          end

          open_now = 5.times.map { |index| make.call(0, 3 + index) }
          pending = 4.times.map { make.call(0, 20) }
          refused = 2.times.map { make.call(0, 22) }
          canceled = 2.times.map { make.call(0, 6) }
          Promises::Reviewer.new(@manager).approve(pending.last)
          refused.each { |promise| Promises::Reviewer.new(@manager).refuse(promise, "Prazo acima do combinado com a diretoria.") }
          canceled.each { |promise| Promises::Canceller.new(@manager).cancel(promise, "Cliente pediu para renegociar.") }

          fulfilled = 3.times.map { make.call(6, 3) }
          late = 2.times.map { make.call(8, 3) }
          broken = 3.times.map { make.call(9, 3) }
          not_approved = 2.times.map { make.call(40, 25, pool: old) }

          rows = [ %w[canal identificador documento titulo data_pagamento valor meio] ]
          fulfilled.each { |promise| rows << payment_row(promise, today - 5, promise.total_cents) }
          # Pagos direto nos títulos, depois da data prometida (ainda dentro da tolerância): a promessa termina cumprida com atraso.
          late.each do |promise|
            promise.promise_bills.includes(:bill).each do |item|
              rows << [ @channels["341-1234-56789"].code, "PL#{item.id}", promise.customer.document, item.bill.number, (today - 3).strftime("%d/%m/%Y"), Money.format(item.total_cents + 2_000), "pix" ]
            end
          end
          # Uma promessa aberta com pagamento parcial ("pago 40%").
          rows << payment_row(open_now.first, today - 1, open_now.first.total_cents * 4 / 10)
          path = @tmp.join("promessas-#{tenant.id}.csv").to_s
          File.write(path, rows.map { |row| row.join(";") }.join("\n") + "\n")
          run_import(tenant, path, kind: "payments", name: "pagamentos-promessas.csv")
          Promises::Daily.new(tenant).apply(today: today)
          [ pending, not_approved, broken ]
        end

        def payment_row(promise, date, cents)
          [ @channels["341-1234-56789"].code, "PR#{promise.id}", promise.customer.document, promise.number, date.strftime("%d/%m/%Y"), Money.format(cents), "pix" ]
        end
    end
  end
end
