module Demo
  class Dataset
    # Réguas (21) na Escola Alfa: as peças e a tarefa do protótipo; "Cobrança PF" (maior atraso do contrato) com o grupo de controle pelo sorteio,
    # o público em promessa ou acordo de fora, os contratos PF até R$ 500 e a trilha padrão, com o fim em D+60; "Mensalidades a vencer" (vencimento
    # da fatura) com o lembrete em D−3 e o fim em D+0; e a "Campanha de fim de ano", desligada. As rodadas dos 3 dias anteriores rodam com os
    # executores simulados (a emissão, pelo fornecedor falso), para a lista de rodadas e a ficha terem história. Nada sai do CRM.
    module CadenceSteps
      # Dias de rodadas antes de hoje: 7 custavam 148 s na recriação (com o "ainda vale?" em lote); 3 bastam para a lista de rodadas e a ficha.
      HISTORY_DAYS = 3
      PIECES = [ [ "Lembrete atraso", "sms" ], [ "Vence em 3 dias", "sms" ], [ "Segunda via", "email" ], [ "Oferta de acordo", "whatsapp" ], [ "Carta aviso", "letter" ] ].freeze

      private
        def cadences(tenant)
          pieces = PIECES.to_h { |name, channel| [ name, MessagePiece.create!(tenant: tenant, name: name, channel: channel) ] }
          task = QueueTask.create!(tenant: tenant, name: "Ligar para negociar", instruction: "Ligar para o responsável financeiro e oferecer o acordo à vista.", due_days: 3)
          segments = cadence_segments(tenant)
          collection = collection_cadence(tenant, pieces, task, segments)
          upcoming = upcoming_cadence(tenant, pieces)
          campaign(tenant, pieces)
          # O despachante da régua (Sidekiq, a cada minuto) grava como "não rodou no dia" as horas dos dias anteriores de toda régua ligada desde antes
          # delas. Ligadas "desde agora" enquanto as rodadas passadas são montadas, ele não as toca; depois, a data volta a 8 dias atrás.
          [ collection, upcoming ].each { |cadence| cadence.update!(enabled: true, enabled_since: Time.current) }
          past_rounds(tenant)
          Cadence.where(id: [ collection.id, upcoming.id ]).update_all(enabled_since: today.beginning_of_day - 8.days)
        end

        def cadence_segments(tenant)
          {
            control: Segment.create!(tenant: tenant, name: "Régua: grupo de controle", subject: "contracts",
                                     expression: { "all" => [ { "path" => "holder.draw", "op" => "lt", "value" => 10 } ] }),
            deals: Segment.create!(tenant: tenant, name: "Régua: promessa ou acordo em dia", subject: "contracts",
                                   expression: { "all" => [ { "any" => [ { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "in", "value" => %w[pending open] } },
                                                                         { "path" => "agreements", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "active_on_time" } } ] } ] }),
            small: Segment.create!(tenant: tenant, name: "Régua: PF até R$ 500", subject: "contracts",
                                   expression: { "all" => [ { "path" => "person_type", "op" => "eq", "value" => "person" }, { "path" => "balance", "op" => "lte", "value" => 50_000 } ] })
          }
        end

        def collection_cadence(tenant, pieces, task, segments)
          pix = Cadences::Catalog.issuable_methods(tenant).first
          small_cells = { 1 => [ sms(pieces["Lembrete atraso"]) ], 5 => [ sms(pieces["Lembrete atraso"]), *(pix ? [ { kind: "issue_instrument", payment_method: pix, params: { "due_days" => 3, "object" => "overdue_bills" } } ] : []) ],
                          15 => [ { kind: "email", piece: pieces["Segunda via"] }, { kind: "whatsapp", piece: pieces["Oferta de acordo"] } ],
                          30 => [ { kind: "proposal", params: { "form" => "cash", "concession" => "max" } } ], 45 => [ { kind: "letter", piece: pieces["Carta aviso"] } ], 60 => [] }
          default_cells = { 5 => [ sms(pieces["Lembrete atraso"]) ], 30 => [ { kind: "proposal", params: { "form" => "installments", "concession" => "min" } } ],
                            45 => [ { kind: "task", queue_task_id: task.id } ] }
          build_cadence(tenant, name: "Cobrança PF", milestone: "contract_arrears", time: "09:30",
                        lanes: [ [ segments[:control], {} ], [ segments[:deals], {} ], [ segments[:small], small_cells ], [ nil, default_cells ] ])
        end

        def upcoming_cadence(tenant, pieces)
          build_cadence(tenant, name: "Mensalidades a vencer", milestone: "bill_due", time: "14:00", days: (1..5).to_a, lanes: [ [ nil, { -3 => [ sms(pieces["Vence em 3 dias"]) ], 0 => [] } ] ])
        end

        def campaign(tenant, pieces)
          build_cadence(tenant, name: "Campanha de fim de ano", milestone: "customer_in_collection", time: "10:00", days: [ 1, 3, 5 ],
                        valid_from: Date.new(today.year, 12, 1), valid_until: Date.new(today.year + 1, 1, 31),
                        lanes: [ [ nil, { 0 => [ { kind: "whatsapp", piece: pieces["Oferta de acordo"] } ], 20 => [ { kind: "proposal", params: { "form" => "cash", "concession" => "max" } } ], 40 => [] } ] ])
        end

        def sms(piece) = { kind: "sms", piece: piece }

        def build_cadence(tenant, name:, milestone:, time:, lanes:, days: (0..6).to_a, valid_from: today - 30, valid_until: nil)
          cadence = Cadence.create!(tenant: tenant, name: name, milestone: milestone, schedule_days: days, schedule_time: time, valid_from: valid_from, valid_until: valid_until)
          columns = {}
          lanes.each do |segment, cells|
            lane = segment ? cadence.add_lane!(segment) : cadence.default_lane
            cells.each do |offset, actions|
              column = columns[offset] ||= cadence.columns.create!(offset_days: offset)
              actions.each_with_index do |spec, index|
                spec = spec.dup
                CadenceAction.create!(lane: lane, column: column, position: index + 1, kind: spec.delete(:kind), message_piece: spec.delete(:piece), **spec)
              end
            end
          end
          cadence
        end

        # As rodadas dos dias anteriores, em ordem, com os comandos executados na hora pelos executores (simulados; a emissão pelo falso).
        def past_rounds(tenant)
          (1..HISTORY_DAYS).to_a.reverse.each do |ago|
            day = today - ago
            slots = Cadence.where(tenant: tenant, enabled: true).filter_map { |cadence| [ cadence, Cadences::Schedule.slot(cadence, day) ] if Cadences::Schedule.slot(cadence, day) }
            slots.group_by(&:last).each do |slot, pairs|
              # Se o despachante gravou a hora antes deste passo (a recriação de 15/11/2026 parou aqui com a chave repetida), ela volta a "prevista".
              pairs.each do |cadence, _|
                CadenceRound.find_or_initialize_by(tenant: tenant, cadence: cadence, scheduled_for: slot)
                            .update!(state: "scheduled", late: false, failure: nil, finished_at: nil, dispatched_at: nil)
              end
              round = Cadences::Round.new(tenant, slot)
              round.decide
              round.prioritize
              round.build
              round.enqueue
              CadenceCommand.where(cadence_round_id: CadenceRound.where(tenant: tenant, scheduled_for: slot).select(:id)).find_each do |command|
                Cadences::Executors.run(command, now: slot + 3.minutes)
              end
            end
          end
        end
    end
  end
end
