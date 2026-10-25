module Agreements
  # Ordem em que um pagamento cobre um título de acordo (11, R227): os encargos de atraso (`late`: multa, juros de mora, correção e honorários do atraso), os
  # juros do parcelamento e, por fim, a composição herdada dos originais, na ordem da 10, R195 (Código Civil, art. 354).
  ORDER = %w[late installment_interest interest inherited_installment_interest inherited_late fine fees correction principal].freeze
  # Os componentes do valor de face do título de acordo (o que a parcela vale sem o atraso); só eles contam no pago do título.
  FACE = (ORDER - %w[late]).freeze
  # Os componentes herdados dos originais, depois dos encargos de atraso e dos juros do parcelamento do próprio título.
  INHERITED_ORDER = (ORDER - %w[late installment_interest]).freeze

  # O que um título de acordo ainda deve numa data (11, R227, R228, R229). Reconstrói o estado do título a partir do que os pagamentos e os abatimentos já
  # cobriram em cada componente, na ordem das datas, para que o resultado não dependa do que ficou na memória: o estorno de um pagamento, que grava linhas
  # negativas, é desfeito pelo mesmo caminho. Os encargos de atraso são os do motor do título de acordo (`Charges::AgreementCalculator`), sobre o principal e a
  # correção herdados que ainda faltam, desde o vencimento (ou desde o último pagamento, M6); a multa se cobra uma vez e não cresce mais (M6).
  class Ledger
    # `date`: a data do pagamento ou do abatimento; `parts`: o que ele cobriu, por componente (o abatimento entra como cobertura, mas não é dinheiro: `cash`).
    Event = Data.define(:date, :parts, :cash)
    # `parts`: quanto falta em cada componente, na ordem de pagamento; `early`: o desconto pela antecipação, que sai dos juros do parcelamento (DA35).
    Due = Data.define(:parts, :early) do
      def total = parts.values.sum

      def late = parts.fetch("late", 0)
    end

    attr_reader :bill

    # `frozen`: os intervalos [de, até ou nil] em que os encargos de atraso não correm (reversão, R239; crédito que cobre o atraso, N17): não voltam depois.
    # `rule`: a regra de atraso congelada no acordo; `tables`: índices até a data (só para a correção); `late_enabled`: política "encargos do título de acordo
    # atrasado" (DA10); `early_discount`: política do pagamento antecipado (DA35); `events`: o que já cobriu o título, em ordem.
    def initialize(bill, rule:, events: [], tables: nil, late_enabled: true, early_discount: true, frozen: [])
      @bill = bill
      @frozen = frozen
      @composition = bill.composition || {}
      @rule = rule
      @tables = tables
      @late_enabled = late_enabled
      @early_discount = early_discount
      @events = events.sort_by(&:date)
    end

    def due_date = @bill.due_date

    # A alocação do crédito de reversão nunca dá desconto de antecipação (R239, AB3).
    def without_early_discount! = (@early_discount = false)

    # Registra o que um pagamento (ou abatimento) acabou de cobrir, para o próximo pagamento do mesmo lote ver o estado novo (a confirmação grava depois).
    def add_event(date, parts, cash: true)
      @events = (@events + [ Event.new(date, parts, cash) ]).sort_by(&:date)
      @covered = nil
    end

    # De onde correm os encargos de atraso: o vencimento, ou a data da quebra no título da quebra (R236).
    def accrues_from = @composition["accrues_from"] ? Date.iso8601(@composition["accrues_from"]) : due_date

    # O valor de face por componente: o que o título herdou dos originais (R224) e os juros do parcelamento.
    def face
      @face ||= begin
        totals = Hash.new(0)
        @composition.fetch("items", []).each { |item| totals[item["component"]] += item["cents"] }
        totals["installment_interest"] += @composition.fetch("installment_interest", 0)
        totals.select { |_, cents| cents.positive? }
      end
    end

    def covered
      @covered ||= @events.each_with_object(Hash.new(0)) { |event, sum| event.parts.each { |component, cents| sum[component] += cents unless component == "late" } }
    end

    # O que ainda falta da face, por componente (nunca abaixo de zero).
    def face_remaining
      face.to_h { |component, cents| [ component, [ cents - covered.fetch(component, 0), 0 ].max ] }
    end

    # A composição que ainda falta, original por original (para o título da quebra, R236): os pedaços da composição menos o que já foi coberto em cada componente, do
    # primeiro pedaço ao último.
    def items_remaining
      left = covered.dup
      @composition.fetch("items", []).filter_map do |item|
        component = item["component"]
        take = [ left.fetch(component, 0), item["cents"] ].min
        left[component] = left.fetch(component, 0) - take
        rest = item["cents"] - take
        { "bill_id" => item["bill_id"], "component" => component, "cents" => rest } if rest.positive?
      end
    end

    def principal_remaining = face_remaining.fetch("principal", 0)
    def correction_remaining = face_remaining.fetch("correction", 0)

    # Algum dinheiro (pagamento vigente) já entrou no título? O abatimento não conta (R229, Z2).
    def paid_any? = @events.any? { |event| event.cash && event.parts.values.sum.positive? }

    # Encargos de atraso devidos em `on`: o que correu menos o que já foi pago (R228, M6).
    def late_owed(on)
      return 0 unless @late_enabled

      owed, = replay(on)
      [ owed, 0 ].max
    end

    # Encargos de atraso por componente (multa, juros, correção, honorários) do que ainda não foi pago: para o arquivo (R244) e para a memória de cálculo.
    def late_breakdown(on)
      return {} unless @late_enabled

      _, last, fine_pending, remaining_principal, remaining_correction = replay(on)
      accrual(remaining_principal, remaining_correction, last, on, fine_pending).components
    end

    # O que o título deve em `on`, em ordem de pagamento (R227): encargos de atraso, juros do parcelamento com o desconto da antecipação, composição.
    def due(on)
      remaining = face_remaining
      parts = {}
      late = late_owed(on)
      parts["late"] = late if late.positive?
      early = early_reduction(on, remaining.fetch("installment_interest", 0))
      interest = remaining.fetch("installment_interest", 0) - early
      parts["installment_interest"] = interest if interest.positive?
      INHERITED_ORDER.each { |component| parts[component] = remaining[component] if remaining.fetch(component, 0).positive? }
      Due.new(parts, early)
    end

    # Pagamento antes do vencimento (DA35, N16): os juros do parcelamento do próprio título são reduzidos na proporção dos dias antecipados sobre os dias do
    # período dele, nunca abaixo de zero. Metade para o par.
    def early_reduction(on, interest_remaining)
      period = @composition["period_days"].to_i
      return 0 unless @early_discount && interest_remaining.positive? && period.positive? && on < due_date

      days = [ (due_date - on).to_i, period ].min
      Simulation.half_even_div(interest_remaining * days, period)
    end

    # O saldo devedor do título em `on` (R225, N7; R230): a amortização que falta, os juros do parcelamento já corridos e os encargos de atraso, sem os juros que
    # ainda não correram. Devolve [os componentes a cobrir, os juros futuros dispensados]. Os juros correm dia a dia dentro do período do título.
    def balance_parts(on)
      remaining = face_remaining
      interest = remaining.fetch("installment_interest", 0)
      period = @composition["period_days"].to_i
      accrued =
        if interest.zero? || period.zero? || on >= due_date then interest
        else interest - early_reduction_unbounded(on, interest, period)
        end
      parts = {}
      late = late_owed(on)
      parts["late"] = late if late.positive?
      parts["installment_interest"] = accrued if accrued.positive?
      INHERITED_ORDER.each { |component| parts[component] = remaining[component] if remaining.fetch(component, 0).positive? }
      [ parts, interest - accrued ]
    end

    def balance(on) = balance_parts(on).first.values.sum

    private
      def early_reduction_unbounded(on, interest, period)
        days = [ (due_date - on).to_i, period ].min
        Simulation.half_even_div(interest * days, period)
      end

      # Percorre os eventos em ordem de data e devolve [devido, data do último acerto, multa ainda por cobrar, principal que falta, correção que falta] em `on`.
      def replay(on)
        remaining_principal = @composition.fetch("items", []).sum { |item| item["component"] == "principal" ? item["cents"] : 0 }
        remaining_correction = @composition.fetch("items", []).sum { |item| item["component"] == "correction" ? item["cents"] : 0 }
        owed = @composition.fetch("opening_late", 0)
        last = accrues_from
        fine_pending = @composition.fetch("fine", true)
        @events.each do |event|
          if event.date > last
            charged = accrual(remaining_principal, remaining_correction, last, event.date, fine_pending)
            owed += charged.total
            fine_pending = false if charged.total.positive?
            last = event.date
          end
          owed -= event.parts.fetch("late", 0)
          remaining_principal = [ remaining_principal - event.parts.fetch("principal", 0), 0 ].max
          remaining_correction = [ remaining_correction - event.parts.fetch("correction", 0), 0 ].max
        end
        if on > last
          charged = accrual(remaining_principal, remaining_correction, last, on, fine_pending)
          owed += charged.total
        end
        [ owed, last, fine_pending, remaining_principal, remaining_correction ]
      end

      # Os encargos de `from` até `to`, sem os dos intervalos congelados (reversão, N17): os juros e a correção desses dias não voltam. A multa não é descontada.
      def accrual(principal, correction, from, to, fine)
        charged = Charges::AgreementCalculator.call(@rule, principal: principal, correction: correction, due: from, paid_on: to, tables: @tables, fine: fine && @composition.fetch("fine", true))
        @frozen.each do |span_from, span_to|
          low = [ from, span_from ].max
          high = [ to, span_to || to ].min
          next unless high > low

          skipped = Charges::AgreementCalculator.call(@rule, principal: principal, correction: correction, due: low, paid_on: high, tables: @tables, fine: false)
          charged = Charges::AgreementCalculator::Result.new(charged.fine, [ charged.interest - skipped.interest, 0 ].max, [ charged.correction - skipped.correction, 0 ].max,
                                                              [ charged.fees - skipped.fees, 0 ].max)
        end
        charged
      end
  end
end
