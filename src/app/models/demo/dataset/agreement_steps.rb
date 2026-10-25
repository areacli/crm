module Demo
  class Dataset
    # Acordos por novação nos estados principais (11): propostas (pendente, aprovada, recusada, cancelada, expirada, não aprovada), acordo aguardando efetivação,
    # ativo em dia e em atraso, quebrado, quitado e revertido. As datas são as de quando teriam acontecido (o relógio viaja); os pagamentos entram por uma
    # importação, pelo número dos títulos de acordo.
    module AgreementSteps
      private
        def agreements(tenant)
          sources = candidates(tenant, 45, min_bills: 2, older_than: 60)
          operator_actor = @operator
          pays = []

          build = lambda do |ago: 0, discount: 2_500, installments: 4, day: 10, mode: "installments", actor: operator_actor|
            comp = Agreements::Caps::COMPONENTS
            first_that_works(sources) do |source|
              input = Agreements::Simulation::Input.new(bill_ids: source[:bills].first(2).map(&:id), mode: mode, discounts_bp: comp.to_h { |c| [ c, %w[fine interest].include?(c) ? discount : 0 ] },
                                                        down_payment_cents: nil, down_payment_on: nil, installments: (installments if mode == "installments"), day: day, replace: false, credit_cents: 0)
              travel_to((today - ago).in_time_zone.change(hour: 14)) { Agreements::Proposal.new(actor, source[:customer]).create(input) }
            end
          end
          accept = lambda do |agreement, ago|
            at = ->(hour, minute) { (today - ago).in_time_zone.change(hour: hour, minute: minute) }
            input = Agreements::Acceptance::Input.new("whatsapp", at.call(14, 50), "phone", at.call(15, 10), nil, agreement.customer_id)
            Agreements::Acceptance.new(@operator).call(agreement, input, now: at.call(15, 30))
            agreement.reload
          end

          # Propostas.
          pending = 2.times.map { build.call(discount: 8_000) }
          refused = build.call(discount: 8_000)
          Agreements::Reviewer.new(@manager).refuse(refused, "Desconto acima do que a diretoria autoriza para este perfil de cliente.")
          approved = 2.times.map { build.call }
          canceled = build.call
          Agreements::Canceller.new(@operator).cancel(canceled, "Cliente desistiu da proposta.")
          build.call(ago: 10)
          build.call(ago: 10, discount: 8_000)

          # Aceitos: um aguardando a entrada e os que a entrada efetivou.
          waiting = accept.call(build.call(ago: 2), 2)
          on_time = 3.times.map { |n| accept.call(build.call(ago: 12 + n), 12 + n).tap { |agreement| pays << [ agreement, 0, today - 10 - n ] } }
          late = accept.call(build.call(ago: 40, day: (today - 10).day), 40).tap { |agreement| pays << [ agreement, 0, today - 39 ] }
          broken = accept.call(build.call(ago: 75, day: (today - 5).day), 75).tap { |agreement| pays << [ agreement, 0, today - 74 ] }
          settled = accept.call(build.call(ago: 20, installments: 3), 20).tap { |agreement| (0..3).each { |n| pays << [ agreement, n, today - 19 ] } }
          reverted = accept.call(build.call(ago: 15), 15).tap { |agreement| pays << [ agreement, 0, today - 14 ] }
          reversing = accept.call(build.call(ago: 14), 14).tap { |agreement| pays << [ agreement, 0, today - 13 ] }

          rows = [ %w[canal identificador documento titulo data_pagamento valor meio] ]
          pays.each do |agreement, number, date|
            title = agreement.titles.find_by(number: Agreements::Titles.number_of(agreement, number)) or next
            rows << [ @channels["341-1234-56789"].code, "AC#{title.id}", agreement.customer.document, title.number, date.strftime("%d/%m/%Y"), Money.format(title.amount_cents), "pix" ]
          end
          path = @tmp.join("acordos-#{tenant.id}.csv").to_s
          File.write(path, rows.map { |row| row.join(";") }.join("\n") + "\n")
          run_import(tenant, path, kind: "payments", name: "pagamentos-acordos.csv")
          Agreements::Daily.new(tenant).apply(today: today)

          Agreements::Reversion.new(@manager).tap do |reversion|
            reversion.open!(reverted.reload, "Cliente pagou os títulos originais por fora.")
            reversion.conclude!(reverted.reload)
            reversion.open!(reversing.reload, "Acordo feito com o cliente errado.")
          end
          [ pending, approved, waiting, on_time, late, broken, settled ]
        end
    end
  end
end
