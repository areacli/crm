module Agreements
  # Que títulos de acordo entram num acordo novo (11, R250, DA29, N11): os títulos de acordo quebrado (forma "parcelas seguem"), o título da quebra e a parte em aberto de acordo
  # encerrado entram como títulos comuns; o título de estorno é título comum e entra sem depender do acordo de origem (AH1). Os títulos de acordo ativo entram só se a política do
  # credor "renegociar acordo vigente" permitir. O acordo em reversão e o acordo ainda aguardando efetivação não cedem títulos.
  module Eligibility
    module_function

    # nil quando o título pode entrar num acordo; senão a chave do motivo, em `agreements.eligibility`.
    def reason(bill, setting)
      return nil if bill.kind_common? || bill.kind_reversal?

      agreement = bill.agreement
      return :reversing if agreement.reversing?

      case agreement.state
      when "broken", "settled", "renegotiated" then nil
      when "active_on_time", "active_late" then Policies.value(setting, "renegotiate_active") == "yes" ? nil : :active
      else :not_open
      end
    end

    # "Só com todos" (M14, padrão): o acordo novo inclui todos os títulos de acordo em aberto do anterior. Devolve o primeiro acordo anterior que ficou incompleto, ou nil.
    def incomplete_previous(bills, setting)
      return nil if Policies.value(setting, "renegotiate_partial") == "partial"

      selected = bills.select { |bill| bill.kind_agreement? || bill.kind_break? }
      selected.group_by(&:agreement_id).each do |agreement_id, items|
        open = Bill.where(agreement_id: agreement_id, kind: %w[agreement break], status: "active").where("amount_cents > paid_cents").pluck(:id)
        return Agreement.find(agreement_id) if (open - items.map(&:id)).any?
      end
      nil
    end
  end
end
