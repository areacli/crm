module Agreements
  # Acordo sobre acordo (11, R250, DA29, N11): os títulos de um acordo anterior entram num acordo novo pelo saldo devedor (a amortização que falta, os juros do parcelamento já corridos e
  # os encargos de atraso, estes dois em componentes herdados com teto de desconto próprio, padrão 0%). O anterior fica com os títulos presos no aceite do novo e só passa a **renegociado**
  # na efetivação do novo, quando não sobra título próprio em aberto (os que sobram, se pagos, também o deixam renegociado, com os restos abaixo do mínimo abatidos, AE2). Enquanto o novo
  # aguarda, o anterior segue vencendo; pagamento a um título preso do anterior, ou a quebra do anterior, cancela o novo (P1).
  module Renegotiation
    REASON = "acordo anterior pago ou quebrado".freeze

    module_function

    # Na efetivação do novo: o anterior sem título próprio em aberto fica renegociado.
    def after_effectuation(previous, successor)
      own = previous.titles.reload
      return if own.any? { |bill| bill.active? || bill.scheduled? }

      return unless own.any?(&:renegotiated?) && %w[active_on_time active_late broken settled].include?(previous.state)

      before = previous.state
      previous.update!(state: "renegotiated", closed_at: Time.current)
      AgreementEvent.log!(previous, "renegotiated", data: { "from" => before, "by" => successor.number })
      Change.record!(tenant_id: previous.tenant_id, subject_type: "agreement", subject_id: previous.id, event: "state_changed", field: "state", before: before, after: "renegotiated", note: successor.number)
    end

    # P1: o acordo novo aguardando efetivação sobre títulos do `previous` é cancelado quando o anterior recebe pagamento ou quebra.
    def cancel_successors(previous, actor: nil, on: Date.current)
      held = Agreement.where(id: AgreementBill.where(bill_id: previous.titles.select(:id), held: true).select(:agreement_id), state: "awaiting_effectuation")
      held.each { |successor| Release.new(actor).call(successor, to: "canceled", reason: REASON, event: "canceled", on: on) }
    end
  end
end
