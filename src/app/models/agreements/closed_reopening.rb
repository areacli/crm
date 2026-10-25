module Agreements
  # O estorno que reabre título num acordo encerrado (quitado ou renegociado) e o teste da soma (11, R233, AE3, AF1, AF6, AG4): se o que reabre, somado aos restos já abatidos por
  # mínimo e às partes em aberto do acordo, fica igual ou abaixo do mínimo para quebrar, o acordo continua encerrado: a parte de título que mantém pagamento vigente é abatida por
  # mínimo e o resto fica em aberto no acordo encerrado. Acima do mínimo, o acordo reabre: volta a ativo (ou a quebrado, se já tinha quebrado), os restos abatidos por mínimo voltam a
  # aberto com os dias de quebra contados do estorno, qualquer que seja a N10 (AA2), e o acordo novo que renegociou os outros títulos não muda (AF1).
  module ClosedReopening
    module_function

    def call(agreement, on:)
      reopened = agreement.titles.where(status: "active").to_a
      return agreement if reopened.empty?

      ledgers = LedgerLoader.new(agreement.tenant, today: on).call(reopened)
      minimum = agreement.minimum_cents
      abated = abated_by_minimum(agreement)
      face = reopened.sum { |bill| ledgers.fetch(bill.id).due(on).parts.except("late").values.sum }
      total = face + abated.values.sum { |items| items.values.sum }
      if minimum.positive? && total <= minimum
        forgive!(agreement, reopened, ledgers, on)
      else
        reopen!(agreement, abated, on)
      end
      agreement
    end

    # A quitação antecipada desfeita reabre o acordo e todos os títulos que ficaram em aberto contam os dias de quebra do estorno (AE9).
    def reopen_after_settlement!(agreement, on) = reopen!(agreement, abated_by_minimum(agreement), on)

    # Os restos abatidos por mínimo do acordo, por título: { título => { componente => centavos } }.
    def abated_by_minimum(agreement)
      rows = Abatement.where(bill_id: agreement.titles.select(:id), kind: "minimum").group(:bill_id, :component).sum(:amount_cents).select { |_, cents| cents.positive? }
      rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) { |((bill_id, component), cents), result| result[bill_id][component] = cents }
    end

    # Continua encerrado: o título reaberto que mantém pagamento vigente e não é parte reaberta por estorno da origem do crédito é abatido por mínimo; os outros ficam em aberto.
    def forgive!(agreement, reopened, ledgers, on)
      forgiven = reopened.select { |bill| ledgers.fetch(bill.id).paid_any? && !bill.composition["no_minimum"] }
      Standing.abate_minimum!(agreement, forgiven.to_h { |bill| [ bill, ledgers.fetch(bill.id).due(on) ] }, on, nil) if forgiven.any?
    end

    # Reabre: os restos abatidos por mínimo voltam a aberto (linhas negativas), os dias de quebra contam do estorno e o acordo volta a ativo ou a quebrado.
    def reopen!(agreement, abated, on)
      abated.each do |bill_id, parts|
        bill = Bill.find(bill_id)
        Abatement.where(bill_id: bill.id, kind: "minimum").group(:payment_id, :component).sum(:amount_cents).select { |_, cents| cents.positive? }.each do |(payment_id, component), cents|
          Abatement.create!(tenant_id: agreement.tenant_id, payment_id: payment_id, bill: bill, kind: "minimum", component: component, amount_cents: -cents)
        end
        face = parts.sum { |component, cents| component == "late" ? 0 : cents }
        bill.update!(paid_cents: [ bill.paid_cents - face, 0 ].max, status: "active", paid_on: nil, composition: (bill.composition || {}).merge("reopened_on" => on.iso8601))
      end
      agreement.titles.where(status: "active").each do |bill|
        bill.update!(composition: bill.composition.merge("reopened_on" => on.iso8601)) unless bill.composition["reopened_on"].to_s >= on.iso8601
      end
      to = agreement.broken_after_effectuation ? "broken" : "active_on_time"
      before = agreement.state
      agreement.update!(state: to, closed_at: nil)
      AgreementEvent.log!(agreement, before == "renegotiated" ? "renegotiated_reopened" : "reopened", data: { "from" => before })
      Change.create!(tenant_id: agreement.tenant_id, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: before, after: to, note: "estorno")
      BrokeFlag.sync!(agreement)
      Standing.refresh!(agreement.reload, today: on) if to == "active_on_time"
    end
  end
end
