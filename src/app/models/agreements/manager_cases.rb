module Agreements
  # Os casos que pedem o gestor, vistos só com "administrar acordos" (17) nos credores em que a pessoa a tem (11, R243, R245a): a pendente que ninguém pode aprovar, o pagamento no prazo
  # importado depois da quebra que não reativou o acordo (R236a), o estorno à espera do gestor (R233, com há quanto tempo espera e o aviso depois dos dias de quebra, AK5), o acordo em
  # reversão há mais que os dias de quebra congelados (R239), o crédito aguardando alocação (R239), o crédito que cobre atraso há mais que os dias de quebra (R232b) e o crédito
  # disponível que cobre a entrada vencida, na política "aviso ao gestor" (U2). Os casos de devolução de crédito estão adiados (MT-25, R232c).
  module ManagerCases
    # `agreement`: o acordo do caso (pode faltar); `customer` e `tenant`: de quem e de qual credor; `detail`: o texto curto; `link`: o caminho que resolve o caso.
    Case = Data.define(:kind, :agreement, :customer, :tenant, :detail, :link)

    module_function

    def for(user)
      tenant_ids = user.tenant_ids_with("administer_agreements")
      return [] if tenant_ids.empty?

      Pending.nobody_can_approve(tenant_ids).map { |agreement| of_agreement("nobody_can_approve", agreement) } +
        reactivation_not_done(tenant_ids).map { |agreement| of_agreement("reactivation_not_done", agreement) } +
        waiting_reversals(tenant_ids) + long_reversions(tenant_ids) + credit_awaiting(tenant_ids) + credit_covering(tenant_ids)
    end

    def of_agreement(kind, agreement, detail: nil, link: nil)
      Case.new(kind, agreement, agreement.customer, agreement.tenant, detail || I18n.l(agreement.valid_until, format: "%d/%m/%Y"), link)
    end

    # Acordo quebrado que depois da quebra recebeu pagamento com data até a quebra e não foi reativado: a política não reativa, ou os títulos liberados mudaram (R236a). Uma consulta só
    # (duas buscas pelos índices parciais de `payments (agreement_id)` e `bills (agreement_id)`), com a data da quebra em Brasília; medido: com 5 mil acordos quebrados, uma consulta por
    # acordo levava 60 s, e a busca com `or` entre as duas, 300 s.
    def reactivation_not_done(tenant_ids)
      Agreement.where(tenant_id: tenant_ids, state: "broken").includes(:customer, :tenant).where(<<~SQL.squish, BrDate.zone_name, BrDate.zone_name)
        exists (select 1 from payments p where p.agreement_id = agreements.id and p.status = 'applied' and p.created_at >= agreements.broken_at and p.paid_on <= (agreements.broken_at at time zone ?)::date)
        or exists (select 1 from bills b join payments p on p.bill_id = b.id where b.agreement_id = agreements.id and p.status = 'applied' and p.created_at >= agreements.broken_at
                   and p.paid_on <= (agreements.broken_at at time zone ?)::date)
      SQL
    end

    # R233, AK5: o estorno que espera a decisão, com os dias de espera; depois dos dias de quebra do acordo, o aviso.
    def waiting_reversals(tenant_ids)
      ReversalWait.where(tenant_id: tenant_ids).waiting.oldest_first.includes(:payment, :tenant, agreement: :customer).map do |wait|
        days = wait.waiting_days
        late = wait.agreement && days > wait.agreement.break_days
        text = I18n.t("agreements.cases.waiting_detail", days: days, amount: Money.format(wait.amount_cents)) + (late ? I18n.t("agreements.cases.waiting_late") : "")
        customer = wait.agreement&.customer || wait.payment.bill&.customer
        Case.new("reversal_waiting", wait.agreement, customer, wait.tenant, text, Rails.application.routes.url_helpers.reversal_waits_path)
      end
    end

    # R239: o acordo em reversão há mais que os dias de quebra congelados nele.
    def long_reversions(tenant_ids)
      Agreement.where(tenant_id: tenant_ids).where.not(reversing_since: nil).where(reverted_at: nil).includes(:customer, :tenant).select do |agreement|
        (Date.current - agreement.reversing_since.to_date).to_i > agreement.break_days
      end.map { |agreement| of_agreement("reversion_long", agreement, detail: I18n.t("agreements.cases.since", date: I18n.l(agreement.reversing_since.to_date, format: "%d/%m/%Y"))) }
    end

    # R239: crédito aguardando alocação nos contratos do credor (o gestor aloca ou transfere).
    def credit_awaiting(tenant_ids)
      sums = Credit.where(tenant_id: tenant_ids, bucket: "awaiting").group(:contract_id).sum(:amount_cents).select { |_, cents| cents.positive? }
      Contract.where(id: sums.keys).includes(:tenant, :customers).map do |contract|
        customer = contract.customers.first
        Case.new("credit_awaiting", nil, customer, contract.tenant, I18n.t("agreements.cases.credit_detail", contract: contract.label, amount: Money.format(sums[contract.id])),
                 customer ? Rails.application.routes.url_helpers.customer_path(customer, anchor: "credito") : nil)
      end
    end

    # R232b, U2: o crédito disponível que cobre o atraso há mais que os dias de quebra (intervalo congelado aberto), e o que cobre a entrada vencida na política "aviso ao gestor".
    def credit_covering(tenant_ids)
      cases = Agreement.where(tenant_id: tenant_ids, state: %w[active_on_time active_late]).where("terms @> ?::jsonb", '{"frozen":[{"kind":"credit","to":null}]}').includes(:customer, :tenant).select do |agreement|
        span = agreement.frozen_spans.find { |item| item["kind"] == "credit" && item["to"].nil? }
        span && (Date.current - Date.iso8601(span["from"])).to_i > agreement.break_days
      end.map { |agreement| of_agreement("credit_covers_overdue", agreement, detail: I18n.t("agreements.cases.credit_covers")) }
      cases + entry_credit_notice(tenant_ids)
    end

    def entry_credit_notice(tenant_ids)
      tenants = Tenant.where(id: tenant_ids).includes(:setting).select { |tenant| Policies.value(tenant.setting, "credit_and_late_down_payment") == "notice" }
      return [] if tenants.empty?

      Agreement.where(tenant_id: tenants.map(&:id), state: %w[active_on_time active_late], effectuated_by: "acceptance").includes(:customer, :tenant).select do |agreement|
        entry = agreement.entry_title
        entry&.active? && Date.current > agreement.deadline_for(entry, agreement.tolerance_days) && CreditBook.balance(entry.contract_id).positive?
      end.map { |agreement| of_agreement("credit_covers_entry", agreement, detail: I18n.t("agreements.cases.credit_covers_entry")) }
    end
  end
end
