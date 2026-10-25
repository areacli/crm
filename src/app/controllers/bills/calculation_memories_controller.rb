module Bills
  # Memória de cálculo do valor atualizado de um título (09, R174): períodos com segmento, regra, índices, taxas, dias e resultado, pelos
  # parâmetros do credor do título. Calculada na hora, só para este título; quem vê a ficha (consultar) vê a memória (R179).
  class CalculationMemoriesController < ApplicationController
    def show
      @bill = Bill.includes(:tenant).find(params[:bill_id])
      authorize @bill, :show?
      tenant = @bill.tenant
      today = Date.current
      input = Charges::Reader.new(tenant, today: today, bill_ids: [ @bill.id ]).to_enum(:each_batch).flat_map(&:itself).first
      if input
        valuation = Charges::Valuation.new(tables: Charges::RuleSet.tables(tenant, today), rules: Charges::RuleSet.rules(tenant), demais_id: Charges::RuleSet.demais_id(tenant),
                                           versions: Charges::RuleHistory.lookup(tenant))
        input.periods = Contract.find(input.contract_id).contract_segments.order(:since, :id).pluck(:since, :segment_id) if input.periods.empty?
        @result = valuation.call(input, memory: true)
      end
      @tenant = tenant
      @today = today
      @can_see_indexes = Current.user.permitted?("change_settings", tenant) || Current.user.permitted?("change_financial_policies", tenant)
      render layout: false
    end
  end
end
