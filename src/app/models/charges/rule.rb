module Charges
  # Regra de encargos efetiva de um segmento (R160), com os percentuais em fração. É o que o cálculo lê; vem do segmento com o que ele herda do
  # credor (R207a). `interest`: "", "fixed" ou "legal". `index`: "", "ipca", "inpc" ou "igpm".
  Rule = Data.define(:name, :fine, :interest, :rate, :form, :index, :fees, :convention, :fine_base) do
    def self.blank(name = "Demais") = new(name, 0.0, "", 0.0, "simple", "", 0.0, "calendar", "corrected")

    # `values`: hash com os campos do segmento (ou da proposta) e `params`: os parâmetros do credor.
    def self.build(values, params)
      pick = ->(own, inherited) { values[own].nil? ? params[inherited] : values[own] }
      index = pick.call(:index_code, :charge_index)
      kind = values[:interest_kind].to_s
      fees = values[:fees_in_contract] ? values[:fees_pct].to_f / 100 : 0.0
      new(values[:name].to_s, pick.call(:fine_pct, :charge_fine_pct).to_f / 100, kind == "none" ? "" : kind, pick.call(:interest_pct, :charge_interest_pct).to_f / 100,
          values[:interest_form].to_s.presence || "simple", index == "none" ? "" : index.to_s, fees,
          pick.call(:days_convention, :charge_days_convention).to_s, pick.call(:fine_base, :charge_fine_base).to_s)
    end

    def charges? = fine.positive? || interest != "" || index != "" || fees.positive?

    def to_h_for_storage = to_h.transform_keys(&:to_s)

    def self.from_storage(hash) = new(*members.map { |member| hash[member.to_s] })
  end
end
