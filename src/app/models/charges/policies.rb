module Charges
  # Políticas do credor que mudam o cálculo (R165, R180, R181).
  Policies = Data.define(:missing_index, :negative_index, :old_legal) do
    def self.of(setting) = new(setting.missing_index_policy, setting.negative_index_policy, setting.old_legal_interest_policy)
    def self.default = new("closed_only", "floor", "selic")
  end
end
