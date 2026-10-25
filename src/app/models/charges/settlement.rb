module Charges
  # O valor atualizado de um título na data de um pagamento, para a baixa por componente (R226): o motor da 09 com os dados do título lidos de uma
  # vez (por lote da carga) e o que a própria carga já alocou nele (M5: o pagamento seguinte é alocado sobre o estado atual). Só existe para credor
  # com alguma regra de encargos; sem ela, o título não tem encargos e a baixa é só do principal.
  class Settlement
    def self.for(tenant, today: Date.current)
      rules = RuleSet.rules(tenant)
      new(tenant, rules, today) if rules.values.any?(&:charges?)
    end

    def initialize(tenant, rules, today)
      @tenant = tenant
      @today = today
      @valuation = Valuation.new(tables: RuleSet.tables(tenant, today), rules: rules, demais_id: RuleSet.demais_id(tenant), versions: RuleHistory.lookup(tenant))
      @inputs = {}
    end

    # Lê os títulos ainda não lidos; um título lido uma vez não é lido de novo (o que a carga aloca fica na memória, não no banco, até gravar).
    def preload(bill_ids)
      missing = bill_ids - @inputs.keys
      return if missing.empty?

      Reader.new(@tenant, today: @today, bill_ids: missing).each_batch { |batch| batch.each { |input| @inputs[input.bill_id] = input } }
      missing.each { |id| @inputs[id] ||= false }
    end

    # { componente => quanto falta } do título em `date`, com o principal limitado ao saldo; nil quando o título não tem valor atualizado (a
    # vencer, ou fora do que o recálculo calcula).
    def due(bill_id, date, balance)
      input = @inputs[bill_id]
      return nil unless input && date > input.due

      result = @valuation.call(input, as_of: date)
      due = result.components.merge("principal" => [ [ result.principal, balance ].min, 0 ].max)
      due.select { |_, cents| cents.positive? }
    end

    # O que o pagamento cobriu entra no estado do título para o próximo pagamento da mesma carga.
    def record(bill_id, date, components)
      input = @inputs[bill_id]
      return unless input

      # O Reader entrega coleções compartilhadas e congeladas para o caso comum: troca, sem mudar no lugar.
      input.dates = input.dates.dup << date if components.values.any?(&:positive?)
      components.each do |component, cents|
        if component == "principal"
          input.payments = input.payments + [ [ date, cents ] ]
        else
          input.paid = input.paid.merge(component => input.paid.fetch(component, 0) + cents)
        end
      end
    end
  end
end
