module Agreements
  # A marca "já quebrou acordo" (11, R248, 08 DS4): fica no contrato dos títulos do acordo que quebrou depois da efetivação, mesmo depois de quitar ou renegociar, e só sai com a
  # reativação (R236a) ou a reversão (R239). Quebra antes da efetivação e cancelamento não contam. O segmento do contrato a lê (`contracts.broke_agreement`).
  module BrokeFlag
    module_function

    def sync!(agreement)
      contract_ids = agreement.agreement_bills.map(&:contract_id).uniq
      contract_ids.each do |contract_id|
        broke = Agreement.joins(:agreement_bills).where(agreement_bills: { contract_id: contract_id }, broken_after_effectuation: true).exists?
        Contract.where(id: contract_id).where.not(broke_agreement: broke).update_all(broke_agreement: broke)
      end
    end
  end
end
