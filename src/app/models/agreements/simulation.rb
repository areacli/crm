module Agreements
  # Simulação do acordo (11, R211 a R216): a base de cada título por componente na data de hoje, o desconto igual para todos os títulos, a entrada e as
  # parcelas (sem juros, Price ou SAC, com o primeiro período irregular), as validações na ordem da R215 e a alçada de quem monta (R216). Não grava nada: a
  # proposta (`Agreements::Proposal`) roda esta mesma simulação dentro da transação e só grava se ela passar. Dinheiro em centavos inteiros; os descontos
  # em centésimos de ponto percentual (50% é 5000), com a divisão inteira arredondada pela NBR 5891 (metade para o par).
  class Simulation
    BILLS_LIMIT = 100

    # `after`: o que resta de cada componente depois do desconto; `credit`: o crédito do contrato usado como abatimento (R223), por componente.
    Row = Data.define(:bill, :base, :discount, :after, :credit) do
      def base_total = base.values.sum
      def discount_total = discount.values.sum
      def credit_total = credit.values.sum
      def value = after.values.sum - credit_total
    end

    Installment = Data.define(:number, :due, :amount_cents, :interest_cents, :amortization_cents, :balance_cents)

    # `error`: a primeira recusa da R215 (nil quando a proposta pode ser gravada); `status`: aprovada ou pendente pela alçada (R216).
    Quote = Data.define(:rows, :tier, :limit, :mode, :discounts, :base_cents, :discount_cents, :value_cents, :net_cents, :down_payment_cents, :down_payment_on,
                        :schedule, :method, :rate_pct, :effective_annual_pct, :total_cents, :interest_cents, :error, :status, :warnings, :calendar, :square, :credit, :limits) do
      def installments = schedule.reject { |row| row.number.zero? }
      def down_payment = schedule.first
      def valid? = error.nil?
      def pending? = status == "pending"
    end

    # O que a tela oferece para os títulos e termos de agora (revisão 12): a faixa da entrada, a entrada inicial (zero concessão: a maior entre o mínimo do item e o
    # do perfil, para caber na alçada de quem negocia), os números de parcelas que a R215 aceita, o limite do perfil em parcelas, o crédito que dá para usar e, em
    # pontos percentuais, o limite do perfil em cada componente para a escolha (à vista ou parcelado).
    Limits = Data.define(:down_min, :down_initial, :down_max, :installment_counts, :profile_installments, :credit_max, :profile_discounts, :minimum_installment)

    # Entrada do formulário. `down_payment_cents` e `down_payment_on` vazios no parcelado valem a entrada mínima e o dia útil seguinte.
    # `auto_down`: a pessoa não mexeu na entrada, que acompanha a entrada inicial. `credit_cents`: quanto do crédito dos contratos o operador usa (R223); vazio, nenhum.
    Input = Data.define(:bill_ids, :mode, :discounts_bp, :down_payment_cents, :down_payment_on, :installments, :day, :replace, :credit_cents, :auto_down) do
      def initialize(credit_cents: 0, auto_down: false, **rest) = super(credit_cents: credit_cents.to_i, auto_down: auto_down, **rest)
    end

    def initialize(user:, customer:, input:, today: Date.current)
      @user = user
      @customer = customer
      @tenant = customer.tenant
      @setting = @tenant.setting
      @input = input
      @today = today
    end

    # Devolve a cotação. Recusa (Refused) o que não é regra do formulário: título que não existe, que não é do cliente, que não está em cobrança ou que outra
    # proposta prende e a que o operador não pediu para substituir.
    def call
      bills = load_bills
      tier = negotiation_tier(bills)
      calendar = Square.calendar_for(@customer, today: @today)
      square = Square.municipality_for(@customer)
      pricing = price(bills)
      rules = Charges::RuleSet.rules(@tenant)
      rows = pricing.rows.map { |row| discounted(row, rules, tier) }
      base = rows.sum(&:base_total)
      discount = rows.sum(&:discount_total)
      after_discount = base - discount
      credit = credit_plan(rows)
      # Zero parcelas é parcela única: sem entrada, e ela é o valor do acordo (revisão 12).
      cash = @input.mode == "cash" || @input.installments.to_i < 1
      # R223, Z8: o crédito como abatimento que cobre o valor do acordo inteiro entra como pagamento da entrada de um acordo à vista.
      if credit.rebate? && credit.total >= after_discount
        credit = CreditUse::Plan.new("down_payment", credit.requested, credit.distribution, credit.offered, credit.error)
        cash = true
      end
      if credit.rebate?
        allocated = CreditUse.allocate_rebate(@setting, rows, credit)
        rows = rows.each_with_index.map { |row, index| row.with(credit: allocated.fetch(index, {}).dup) }
      end
      value = after_discount
      net = rows.sum(&:value) # o valor líquido: o valor do acordo menos o crédito usado como abatimento (R223)
      limit = AgreementLimit.for(profile, tier)
      down_on = calendar.next_business(@input.down_payment_on || (@today + 1))
      down = cash ? net : (@input.down_payment_cents || (@input.auto_down ? initial_down(net, tier, limit) : minimum_down(net, tier)))
      schedule, method, rate, interest = build_schedule(net, down, down_on, tier, calendar, cash)
      annual = method == "none" || rate.zero? ? BigDecimal("0") : (((1 + rate / 100)**12 - 1) * 100).round(4)
      quote = Quote.new(rows: rows, tier: tier, limit: limit, mode: @input.mode, discounts: @input.discounts_bp, base_cents: base, discount_cents: discount, value_cents: value,
                        net_cents: net, down_payment_cents: down, down_payment_on: down_on, schedule: schedule, method: method, rate_pct: rate, effective_annual_pct: annual,
                        total_cents: schedule.sum(&:amount_cents), interest_cents: interest, error: nil, status: "approved", warnings: warnings(bills, square), calendar: calendar, square: square,
                        credit: credit, limits: limits_for(rows, after_discount, net, down, down_on, tier, limit, calendar, cash))
      quote = quote.with(mode: "cash") if cash
      error = first_error(quote, tier)
      quote = quote.with(error: error)
      quote.with(status: within_limits?(quote, limit) ? "approved" : "pending")
    end

    # O perfil do usuário no credor do cliente (MT-2): a alçada de cada credor é a do perfil dele nele.
    def profile
      @profile ||= Membership.active.where(user_id: @user.id, tenant_id: @tenant.id).includes(:profile).first&.profile or raise Refused, I18n.t("agreements.refused.no_profile")
    end

    # Metade para o par, em inteiros: n ÷ d.
    def self.half_even_div(numerator, denominator)
      quotient, remainder = numerator.divmod(denominator)
      twice = remainder * 2
      twice > denominator || (twice == denominator && quotient.odd?) ? quotient + 1 : quotient
    end

    private
      # R211: de 1 a 100 títulos do cliente, em cobrança; os que uma proposta vigente prende só entram para substituí-la (R218).
      def load_bills
        ids = Array(@input.bill_ids).filter_map { |id| id.to_s.presence&.to_i }.uniq
        raise Refused.new(I18n.t("agreements.refused.bills_required"), field: "bill_ids") if ids.empty?
        raise Refused.new(I18n.t("agreements.refused.bills_limit", max: BILLS_LIMIT), field: "bill_ids") if ids.size > BILLS_LIMIT

        bills = Bill.where(id: ids, tenant_id: @tenant.id, customer_id: @customer.id).includes(:contract, :agreement).order(:due_date, :id).to_a
        raise Refused.new(I18n.t("agreements.refused.bill_unknown"), field: "bill_ids") if bills.size != ids.size

        bills.each do |bill|
          raise Refused.new(I18n.t("agreements.refused.bill_not_open", number: bill.number), field: "bill_ids") unless bill.active? && bill.balance_cents.positive?
          # R250: o título de acordo entra se o acordo dele permite (quebrado, encerrado ou, pela política, ativo); o de estorno é comum.
          why = Eligibility.reason(bill, @setting)
          raise Refused.new(I18n.t("agreements.eligibility.#{why}", number: bill.number), field: "bill_ids") if why
        end
        previous = Eligibility.incomplete_previous(bills, @setting)
        raise Refused.new(I18n.t("agreements.eligibility.partial", agreement: previous.number), field: "bill_ids") if previous
        held = AgreementBill.where(bill_id: ids, held: true).includes(:agreement).group_by(&:bill_id)
        bills.each do |bill|
          holders = held[bill.id] or next
          agreement = holders.first.agreement
          next if @input.replace && agreement.proposal?

          raise Refused.new(I18n.t("agreements.refused.bill_held", number: bill.number, agreement: agreement.number), field: "bill_ids")
        end
        bills
      end

      # R211, DS8: o segmento do contrato; com títulos de mais de um contrato, o do contrato mais atrasado, e no empate o de maior saldo. Contrato sem segmento
      # vale "Demais" (M11).
      def negotiation_tier(bills)
        contracts = bills.group_by(&:contract).map do |contract, items|
          overdue = items.map { |bill| bill.days_overdue(@today) }.max
          [ overdue, items.sum(&:balance_cents), contract ]
        end
        contract = contracts.max_by { |overdue, balance, _| [ overdue, balance ] }.last
        Promises::Limits.tier_of(contract)
      end

      # A base de cada título (R211, R250): o título comum pelo valor atualizado da 09; o título de acordo, da quebra ou de estorno pelo saldo devedor de hoje, com a composição que falta e,
      # em componentes herdados próprios, os juros do parcelamento já corridos e os encargos de atraso (sem os juros que ainda não correram).
      def price(bills)
        common, ledgered = bills.partition(&:kind_common?)
        pricing = Promises::Pricing.quote(@tenant, common, @today)
        return pricing if ledgered.empty?

        ledgers = LedgerLoader.new(@tenant, today: @today).call(ledgered)
        by_bill = pricing.rows.index_by { |row| row.bill.id }
        ledgered.each do |bill|
          parts, = ledgers.fetch(bill.id).balance_parts(@today)
          components = parts.to_h { |component, cents| [ { "late" => "inherited_late", "installment_interest" => "inherited_installment_interest" }.fetch(component, component), cents ] }
          by_bill[bill.id] = Promises::Pricing::Row.new(bill, components.select { |_, cents| cents.positive? })
        end
        Promises::Pricing::Quote.new(bills.map { |bill| by_bill.fetch(bill.id) }, @today)
      end

      def discounted(row, rules, tier)
        discount = {}
        after = {}
        row.components.each do |component, cents|
          part = self.class.half_even_div(cents * @input.discounts_bp.fetch(component, 0), 10_000)
          discount[component] = part
          after[component] = cents - part
        end
        recompute_fees!(row, discount, after, rules) if fees_on_negotiated? && row.components.key?("fees")
        after.delete_if { |_, cents| cents.zero? }
        discount.delete_if { |_, cents| cents.zero? }
        Row.new(row.bill, row.components, discount, after, {})
      end

      # O plano do crédito dos contratos (R223, R223a): o que o operador pediu, distribuído pelos contratos dos títulos conforme as políticas.
      def credit_plan(rows)
        oldest = {}
        rows.each { |row| oldest[row.bill.contract_id] = [ oldest[row.bill.contract_id], row.bill.due_date ].compact.min }
        CreditUse.plan(@setting, credit_values(rows), oldest, @input.credit_cents)
      end

      def credit_values(rows)
        rows.each_with_object(Hash.new(0)) { |row, values| values[row.bill.contract_id] += row.after.values.sum }
      end

      # R212, DA30: os honorários são recalculados pela taxa do contrato sobre o resultado dos outros componentes, e só então recebe o desconto.
      def recompute_fees!(row, discount, after, rules)
        rate = rules[row.bill.contract.tier_id || Charges::RuleSet.demais_id(@tenant)]&.fees.to_f
        # No acordo sobre acordo, os honorários são recalculados só sobre o principal e a correção herdados (R212).
        base = (row.bill.kind_common? ? %w[principal correction fine interest] : %w[principal correction]).sum { |component| after.fetch(component, 0) }
        recomputed = Charges::Calculator.round_cents(base * rate)
        part = self.class.half_even_div(recomputed * @input.discounts_bp.fetch("fees", 0), 10_000)
        # O que o recálculo tira dos honorários é desconto: a soma do acordo tem de fechar com a base menos os descontos (revisão 12).
        discount["fees"] = part + [ row.components.fetch("fees", 0) - recomputed, 0 ].max
        after["fees"] = recomputed - part
      end

      def fees_on_negotiated? = Policies.value(@setting, "fees") == "on_negotiated"

      def minimum_down(net, tier) = (net * tier.agreement_min_down_payment_pct + 99) / 100

      def initial_down(net, tier, limit) = [ minimum_down(net, tier), (net * limit.min_down_payment_pct + 99) / 100 ].max

      def limits_for(rows, after_discount, net, down, down_on, tier, limit, calendar, cash)
        kind = cash ? "cash" : "installment"
        floor = minimum_down(net, tier)
        offered = CreditUse.usable(@setting, credit_values(rows)).values.sum
        cap = Policies.value(@setting, "credit_entry") == "rebate" ? after_discount : down
        Limits.new(down_min: floor, down_initial: initial_down(net, tier, limit), down_max: [ net - tier.agreement_min_installment_cents, floor ].max,
                   installment_counts: installment_counts(net, cash ? floor : down, down_on, tier, calendar), profile_installments: limit.max_installments,
                   credit_max: [ offered, cap ].min, profile_discounts: Caps.normalize(limit.caps)[kind], minimum_installment: tier.agreement_min_installment_cents)
      end

      # De 1 ao máximo do item, sem os números que deixariam alguma parcela abaixo da mínima (a R215 os recusaria). Quanto mais parcelas, menor cada uma: basta achar a primeira que não serve.
      def installment_counts(net, down, down_on, tier, calendar)
        top = [ tier.agreement_max_installments.to_i, 1 ].max
        return [ 1 ] if down >= net

        parameters = Parameters.installment(@setting, tier)
        day = valid_day(down_on)
        too_small = (1..top).bsearch do |count|
          rows, = amortize(net - down, count, due_dates(count, day, down_on, calendar), down_on, parameters)
          rows.any? { |row| row.amount_cents < tier.agreement_min_installment_cents }
        end
        (1..[ too_small ? too_small - 1 : top, 1 ].max).to_a
      end

      def valid_day(down_on) = @input.day.to_i.between?(1, 28) ? @input.day.to_i : [ down_on.day, 28 ].min

      def due_dates(count, day, down_on, calendar)
        (1..count).map { |k| calendar.next_business(Date.new(down_on.year, down_on.month, 1).next_month(k).change(day: day)) }
      end

      # Entrada e parcelas (R213, R214): vencimentos mensais no dia escolhido, a primeira no mês seguinte ao da entrada, cada um em dia útil.
      def build_schedule(net, down, down_on, tier, calendar, cash)
        parameters = Parameters.installment(@setting, tier)
        entry = Installment.new(0, down_on, down, 0, down, net - down)
        return [ [ entry ], "none", BigDecimal("0"), 0 ] if cash || down >= net

        count = @input.installments.to_i
        # O dia fora de 1 a 28 é recusado (R215), mas a conta mostrada continua sendo a do acordo inteiro, nunca só a da entrada.
        dues = due_dates(count, valid_day(down_on), down_on, calendar)
        rows, interest = amortize(net - down, count, dues, down_on, parameters)
        [ [ entry, *rows ], parameters.method, parameters.rate_pct, interest ]
      end

      # Sem juros, Price ou SAC sobre o valor líquido menos a entrada (R214). Primeiro período irregular (N15): a prestação é a da tabela e a primeira soma os juros dos dias
      # acima (ou abaixo) de 30, pela taxa ÷ 30; na alternativa, a prestação é recalculada e as parcelas ficam iguais. As seguintes contam um mês cada.
      def amortize(principal, count, dues, down_on, parameters)
        rate = parameters.rate_pct.to_f / 100
        days = (dues.first - down_on).to_i
        recalculated = Policies.value(@setting, "first_period") == "recalculated"
        if parameters.method == "none" || rate.zero?
          each, rest = principal.divmod(count)
          balance = principal
          return [ dues.each_with_index.map do |due, index|
            amount = index == count - 1 ? each + rest : each
            balance -= amount
            Installment.new(index + 1, due, amount, 0, amount, balance)
          end, 0 ]
        end
        pmt = parameters.method == "price" ? price_payment(principal, count, rate, days, recalculated) : nil
        balance = principal
        total_interest = 0
        rows = dues.each_with_index.map do |due, index|
          last = index == count - 1
          regular = Charges::Calculator.round_cents(balance * rate)
          interest = index.zero? ? Charges::Calculator.round_cents(balance * rate * days / 30.0) : regular
          interest = Charges::Calculator.round_cents(balance * rate * days / 30.0) if index.zero? && recalculated && parameters.method == "price"
          amortization =
            if last then balance
            elsif parameters.method == "price" then recalculated && index.zero? ? pmt - interest : pmt - regular
            else principal / count
            end
          amount = amortization + interest
          balance -= amortization
          total_interest += interest
          Installment.new(index + 1, due, amount, interest, amortization, balance)
        end
        [ rows, total_interest ]
      end

      # Prestação da tabela Price: P·i ÷ (1 − (1+i)^−n). Recalculada com o primeiro período irregular, todas as parcelas saem iguais.
      def price_payment(principal, count, rate, days, recalculated)
        if recalculated
          grown = principal * (1 + rate * days / 30.0)
          annuity = count > 1 ? (1 - (1 + rate)**-(count - 1)) / rate : 0
          Charges::Calculator.round_cents(grown / (1 + annuity))
        else
          Charges::Calculator.round_cents(principal * rate / (1 - (1 + rate)**-count))
        end
      end

      def warnings(bills, square)
        list = []
        list << I18n.t("agreements.warnings.city_unrecognized") if square.nil?
        responsible = Agreements::Parties.financial_responsibles(bills.map(&:contract))
        list << I18n.t("agreements.warnings.no_contact") if responsible.any? && responsible.none? { |customer| customer.contacts.any? { |contact| contact.status_valid? && !contact.address? } }
        list
      end

      # R215, na ordem da especificação; devolve a primeira recusa, ou nil.
      def first_error(quote, tier)
        discount_error(quote) ||
          credit_error(quote) ||
          (I18n.t("agreements.refused.total_forgiveness") if quote.value_cents <= 0) ||
          installments_error(quote, tier) ||
          down_payment_error(quote, tier) ||
          (I18n.t("agreements.refused.total_forgiveness") if forgiveness?(quote)) ||
          (I18n.t("agreements.refused.sum_below_debt") if sum_below_debt?(quote)) ||
          minimum_to_break_error(quote)
      end

      # Revisão 12: o desconto vai até 100% do valor de cada componente, e não há recusa por teto: quem decide se a proposta nasce aprovada ou pendente é o limite do perfil
      # (R216), e o teto do item só limita o que um perfil pode ter (R209). Sem ninguém que a cubra, a proposta pendente vence pela validade (R217).
      def discount_error(quote)
        quote.discounts.each_value { |bp| return I18n.t("agreements.refused.discount_range") if bp.negative? || bp > 10_000 }
        nil
      end

      # R223: o crédito pedido não passa do que as políticas deixam usar nem, como pagamento da entrada, da entrada.
      def credit_error(quote)
        plan = quote.credit
        return I18n.t("agreements.refused.credit_above", available: Money.format(plan.offered)) if plan.error == :above_available
        return I18n.t("agreements.refused.credit_above_down", down: Money.format(quote.down_payment_cents)) if plan.down_payment? && plan.total > quote.down_payment_cents

        nil
      end

      def installments_error(quote, tier)
        return nil if quote.mode == "cash"

        count = @input.installments.to_i
        return I18n.t("agreements.refused.installments_above", max: tier.agreement_max_installments) if count > tier.agreement_max_installments
        return I18n.t("agreements.refused.day_range") unless @input.day.to_i.between?(1, 28)

        small = quote.installments.find { |row| row.amount_cents < tier.agreement_min_installment_cents }
        small ? I18n.t("agreements.refused.installment_minimum", min: Money.format(tier.agreement_min_installment_cents)) : nil
      end

      def down_payment_error(quote, tier)
        net = quote.net_cents
        down = quote.down_payment_cents
        earliest = quote.calendar.next_business(@today + 1)
        latest = [ @today + tier.agreement_down_payment_days, earliest ].max
        requested = @input.down_payment_on
        if quote.mode != "cash"
          return I18n.t("agreements.refused.down_minimum", pct: tier.agreement_min_down_payment_pct, min: Money.format(minimum_down(net, tier))) if down * 100 < net * tier.agreement_min_down_payment_pct
          return I18n.t("agreements.refused.down_below_net") if down >= net
        end
        return I18n.t("agreements.refused.down_due_range", from: I18n.l(earliest, format: "%d/%m/%Y"), to: I18n.l(latest, format: "%d/%m/%Y")) if requested && (requested <= @today || requested > latest)

        nil
      end

      # Revisão 12: o acordo nunca termina com a soma das parcelas abaixo da dívida (base menos descontos). O crédito usado como abatimento já pagou a parte dele.
      def sum_below_debt?(quote) = quote.schedule.sum(&:amount_cents) + (quote.credit.rebate? ? quote.credit.total : 0) < quote.value_cents

      # Todos os componentes com 100% de desconto: perdão total não passa por acordo (R215).
      def forgiveness?(quote)
        quote.value_cents <= 0 || Caps::COMPONENTS.all? { |component| quote.discounts.fetch(component, 0) >= 10_000 }
      end

      # W3, Z3: a entrada e cada parcela precisam ser maiores que o mínimo para quebrar (R229).
      def minimum_to_break_error(quote)
        minimum = minimum_to_break_cents(quote.net_cents)
        return nil if minimum.zero?
        return nil if quote.schedule.all? { |row| row.amount_cents > minimum }

        I18n.t("agreements.refused.minimum_to_break", min: Money.format(minimum))
      end

      def minimum_to_break_cents(net)
        policy = Policies.value(@setting, "minimum_to_break")
        case policy["kind"]
        when "percent" then net * policy["value"] / 10_000
        when "tolerance" then Policies.tolerance_cents(@setting, "agreement", net)
        else policy["value"]
        end
      end

      # R216: dentro dos limites do perfil de quem monta a proposta nasce aprovada; fora deles e dentro das variáveis do segmento, pendente.
      def within_limits?(quote, limit)
        Agreements::Limits.covers?(limit, quote_figures(quote))
      end

      def quote_figures(quote)
        Agreements::Limits::Figures.new(quote.mode, quote.discounts, quote.installments.size, quote.down_payment_cents, quote.net_cents, quote.discount_cents)
      end
  end
end
