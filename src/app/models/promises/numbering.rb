module Promises
  # Número da promessa, dado quando ela fica aberta (R187a): sequência por credor, no banco, sem repetir mesmo com dois registros ao mesmo tempo.
  # A pendente não tem número e não libera meio de pagamento (DP9).
  module Numbering
    module_function

    def next_for(tenant_id)
      # A linha do credor é travada e o contador sobe de um em um (o banco serializa dois pedidos ao mesmo tempo).
      sequence = TenantSetting.transaction do
        setting = TenantSetting.lock.find_by!(tenant_id: tenant_id)
        setting.increment!(:promise_sequence)
        setting.promise_sequence
      end
      Promises.format_number(sequence)
    end
  end
end
