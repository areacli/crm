# Encargos e valor atualizado (especificação 09): regra do segmento, tabelas de índices por dia, cálculo de um título, recálculo por credor,
# conferência do impacto e alocação dos pagamentos por componente (R226). O cálculo é Ruby puro, sem banco, e os exemplos da especificação
# são testes ao centavo.
module Charges
  # Ordem em que um pagamento cobre os componentes (10, R195; Código Civil, art. 354).
  ORDER = %w[interest fine fees correction principal].freeze
end
