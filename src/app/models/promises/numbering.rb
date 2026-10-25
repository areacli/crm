module Promises
  # Número da promessa, dado quando ela fica aberta (R187a): sequência por credor, no banco, sem repetir mesmo com dois registros ao mesmo tempo.
  # A pendente não tem número e não libera meio de pagamento (DP9).
  module Numbering
    Sql = Portfolio::Sql

    module_function

    def next_for(tenant_id)
      sequence = Sql.one("update tenant_settings set promise_sequence = promise_sequence + 1 where tenant_id = ? returning promise_sequence", tenant_id)
      Promises.format_number(sequence.fetch("promise_sequence").to_i)
    end
  end
end
