module Agreements
  # 17, R420: um acordo só reúne títulos de um mesmo sistema, e o sistema do título é o do contrato dele (R406). Com títulos que podem entrar em mais de
  # um sistema, a tela pergunta o sistema antes da simulação e passa a mostrar só os títulos dele; com um só, nada muda.
  class SystemChoice
    attr_reader :systems, :chosen

    # `bills` com o contrato carregado; `blocked_ids`: os que não podem entrar (preso a um acordo, ou o acordo de origem não deixa renegociar).
    def initialize(bills, blocked_ids, chosen_id)
      ids = bills.reject { |bill| blocked_ids.include?(bill.id) }.map { |bill| bill.contract.source_system_id }.uniq
      @systems = ids.size > 1 ? SourceSystem.where(id: ids).sort_by { |system| system.name.downcase } : []
      @chosen = @systems.find { |system| system.id == chosen_id.to_i }
    end

    # Há mais de um sistema e nenhum foi escolhido: a tela pergunta.
    def pending? = @systems.any? && @chosen.nil?

    def filter(bills) = @chosen ? bills.select { |bill| bill.contract.source_system_id == @chosen.id } : bills

    # Quantos títulos e quanto de saldo cada sistema tem, para a pergunta.
    def totals(bills)
      bills.group_by { |bill| bill.contract.source_system_id }.transform_values { |items| [ items.size, items.sum(&:balance_cents) ] }
    end
  end
end
