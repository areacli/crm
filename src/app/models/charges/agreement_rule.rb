module Charges
  # Parâmetros de encargos de atraso de um título de acordo, congelados no acordo (R207a, R210, R228): percentuais em fração, convenção de dias dos
  # juros (`thirty`: taxa ÷ 30 por dia corrido, como o boleto; `calendar`: fração do mês do calendário), base da multa (`corrected`: principal e
  # correção herdados; `face`: só o principal herdado), forma dos juros, índice de correção (vazio, sem correção) e honorários.
  AgreementRule = Data.define(:fine, :rate, :form, :convention, :fine_base, :index, :fees) do
    def self.blank = new(0.0, 0.0, "simple", "thirty", "corrected", "", 0.0)

    def charges? = fine.positive? || rate.positive? || index != "" || fees.positive?

    def to_storage = to_h.transform_keys(&:to_s)

    def self.from_storage(hash) = new(*members.map { |member| hash[member.to_s] })
  end
end
