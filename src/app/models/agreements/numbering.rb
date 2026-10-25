module Agreements
  # Número do acordo, dado quando a proposta é gravada (R210): sequência por credor, no banco, sem repetir mesmo com duas propostas ao mesmo tempo.
  module Numbering
    Sql = Portfolio::Sql

    module_function

    def next_for(tenant_id)
      sequence = Sql.one("update tenant_settings set agreement_sequence = agreement_sequence + 1 where tenant_id = ? returning agreement_sequence", tenant_id)
      Agreements.format_number(sequence.fetch("agreement_sequence").to_i)
    end
  end
end
