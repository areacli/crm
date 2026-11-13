# Histórico do título (R100): versões do valor, pagamentos aplicados, estornos e divergências, em ordem de data.
class BillsController < ApplicationController
  def show
    @bill = Bill.includes(:customer, :contract, :tenant).find(params[:id])
    authorize @bill
    @history = Portfolio::BillHistory.new(@bill, system_names: SourceSystem.names_if_several(@bill.tenant_id))
    situation
    calculation_memory
  end

  private
    # O que a ficha mostrava no detalhe da linha (padrões de interface, revisão 27): o valor atualizado por componente (09, R174), a promessa ou o acordo que
    # prende o título e o acordo que o renegociou. Consultas: chave de `bill_valuations` e os índices parciais dos títulos presos.
    def situation
      @valuation = BillValuation.find_by(bill_id: @bill.id) if @bill.active?
      @held_promise = PaymentPromiseBill.where(bill_id: @bill.id, held: true).includes(:promise).first&.promise
      return unless AgreementPolicy.new(Current.user, Agreement.new(tenant: @bill.tenant)).show?

      @held_agreement = AgreementBill.where(bill_id: @bill.id, held: true).includes(:agreement).first&.agreement unless @bill.renegotiated?
      @renegotiated_by = AgreementBill.joins(:agreement).where(bill_id: @bill.id, agreements: { state: %w[active_on_time active_late broken settled renegotiated] })
                                      .includes(:agreement).first&.agreement if @bill.renegotiated?
    end

    # Memória de cálculo do valor atualizado (09, R174, revisão 7): períodos com o item do enquadramento, regra, índices, taxas, dias e resultado, pelos
    # parâmetros do credor do título. Calculada na hora, só para este título; quem vê o título (consultar) vê a memória (R179). Sem valor atualizado, nil.
    def calculation_memory
      tenant = @bill.tenant
      @today = Date.current
      input = Charges::Reader.new(tenant, today: @today, bill_ids: [ @bill.id ]).to_enum(:each_batch).flat_map(&:itself).first
      if input
        valuation = Charges::Valuation.new(tables: Charges::RuleSet.tables(tenant, @today), rules: Charges::RuleSet.rules(tenant), demais_id: Charges::RuleSet.demais_id(tenant),
                                           versions: Charges::RuleHistory.lookup(tenant))
        input.periods = Contract.find(input.contract_id).contract_tiers.order(:since, :id).pluck(:since, :tier_id) if input.periods.empty?
        @memory = valuation.call(input, memory: true)
      end
      @can_see_indexes = Current.user.permitted?("change_settings", tenant) || Current.user.permitted?("change_financial_policies", tenant)
    end
end
