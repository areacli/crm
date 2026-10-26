module Agreements
  # Número do acordo, dado quando a proposta é gravada (R210): sequência por credor, no banco, sem repetir mesmo com duas propostas ao mesmo tempo.
  module Numbering
    module_function

    def next_for(tenant_id)
      # A linha do credor é travada e o contador sobe de um em um (o banco serializa dois pedidos ao mesmo tempo).
      sequence = TenantSetting.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant_id)
        setting.increment!(:agreement_sequence)
        setting.agreement_sequence
      end
      Agreements.format_number(sequence)
    end
  end
end
