module Agreements
  # Tarefa diária dos acordos de um credor (11, R217, R234; O8): a validade da proposta (a aprovada sem aceite no fim do último dia da validade fica expirada, e a
  # pendente sem aprovação, não aprovada; os títulos ficam livres), a quebra por atraso de entrada ou de parcela e a situação dos acordos ativos. As etapas seguintes
  # acrescentam o crédito e o arquivo do dia.
  class Daily
    NAME = "agreements_daily"
    Sql = Portfolio::Sql

    def initialize(tenant) = @tenant = tenant

    def call(today: Date.current)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      count = apply(today: today)
      # R244: as novidades do dia para o credor, e a limpeza dos arquivos com mais de 30 dias.
      Archive.new(@tenant).export!("daily", today: today)
      AgreementExport.purge!
      run.update!(status: :succeeded, finished_at: Time.current, processed: count)
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    end

    # Devolve quantas propostas mudaram de estado.
    def apply(today: Date.current)
      changed = []
      ApplicationRecord.transaction do
        changed += expire("approved", "expired", "expired", today)
        changed += expire("pending", "not_approved", "not_approved", today)
        # R232b, DA23, U2, N17: o crédito do contrato é usado ou suspende a quebra antes de avaliá-la.
        cover = CreditCover.new(@tenant)
        changed += cover.before_review(today)
        # R234: a quebra (entrada, parcelas) e, nos que seguem ativos, a situação em dia ou em atraso (R229).
        changed += review(today)
        changed += cover.after_break(today)
      end
      Broadcast.changed(@tenant, changed.map(&:customer_id).uniq.first(200)) if changed.any?
      changed.size
    end

    private
      # R234, R229: só os acordos com algum título vencido além da tolerância (a entrada, antes da efetivação) podem quebrar ou mudar de em dia para em atraso, e um pagamento já
      # reavalia o acordo na confirmação. A consulta usa o dia corrido (conservadora: o dia útil só adia o fim do prazo) e o índice `agreements (tenant_id, state, valid_until)`;
      # com 50 mil acordos, só os candidatos passam pelo cálculo em Ruby.
      def review(today)
        ids = Sql.rows(<<~SQL, @tenant.id, today).map { |row| row["id"].to_i }
          select distinct a.id from agreements a join bills b on b.agreement_id = a.id
          where a.tenant_id = ? and a.state in ('awaiting_effectuation', 'active_on_time', 'active_late')
            and b.status in ('active', 'scheduled') and b.due_date + coalesce((a.terms->'segment'->>'tolerance_days')::int, 0) < ?::date
        SQL
        changed = []
        ids.each_slice(500) do |slice|
          agreements = Agreement.where(id: slice).to_a
          # O credor já está lido: sem isso cada acordo leria o credor e a configuração dele (duas consultas por acordo, medido: 3 ms cada).
          agreements.each { |agreement| agreement.association(:tenant).target = @tenant }
          titles, ledgers = LedgerLoader.new(@tenant, today: today).for_agreements(agreements)
          credits = Credit.available.where(contract_id: titles.values.flatten.map(&:contract_id).uniq).group(:contract_id).sum(:amount_cents)
          causes = agreements.to_h { |agreement| [ agreement, Breaker.cause(agreement, today, titles: titles.fetch(agreement.id, []), ledgers: ledgers, credits: credits) ] }
          breaks, others = agreements.partition { |agreement| causes[agreement] }
          Breaker.break_many!(breaks.map { |agreement| [ agreement, causes[agreement] ] }, today: today)
          changed += breaks
          changed += Standing.refresh_many(others.reject(&:state_awaiting_effectuation?), today: today, loaded: [ titles, ledgers ])
        end
        changed
      end

      # R217: vale até o fim do último dia da validade; no dia seguinte a proposta vence.
      def expire(from, to, event, today)
        agreements = Agreement.where(tenant_id: @tenant.id, state: from).where(valid_until: ...today).lock.to_a
        agreements.each do |agreement|
          agreement.update!(state: to, closed_at: Time.current)
          agreement.agreement_bills.update_all(held: false)
          AgreementEvent.log!(agreement, event)
          Change.create!(tenant_id: @tenant.id, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: from, after: to)
        end
        agreements
      end
  end
end
