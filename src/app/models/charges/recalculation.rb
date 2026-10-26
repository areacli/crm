module Charges
  # Recálculo do valor atualizado de todos os títulos vencidos em cobrança de um credor (R173): diário, depois de confirmar uma carga, uma importação
  # de pagamentos ou estornos, uma mudança de encargos, de segmentos ou de política e a correção de um índice. Uma execução por credor, com o próprio
  # registro (O8, R173a); a falha de um credor não impede os outros. Grava dentro da trava por credor dos segmentos e apaga e regrava por COPY.
  class Recalculation
    NAME = "values_recalculation"
    RUNNING_WINDOW = 10.minutes
    Sql = Portfolio::Sql
    COLUMNS = %w[bill_id tenant_id principal_cents corrected_principal_cents fine_cents interest_cents fees_cents total_cents calculated_on].freeze

    def initialize(tenant) = @tenant = tenant

    # Marca o recálculo como em andamento (a aba Segmentos mostra "valores sendo recalculados", R173) e devolve o registro.
    def self.start(tenant, reason: nil)
      run = TaskRun.create!(tenant: tenant, name: NAME, started_at: Time.current, note: reason)
      Segments::Broadcast.changed(tenant)
      run
    end

    # Executa e fecha o registro: `run` é o de `start` (ou nil, e cria um). A falha guarda só o tipo do erro (D5).
    def call(run = nil, today: Date.current)
      run ||= TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      count = apply(today: today)
      run.update!(status: :succeeded, finished_at: Time.current, processed: count)
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    ensure
      Segments::Broadcast.changed(@tenant)
    end

    # Devolve quantos títulos foram calculados.
    def apply(today: Date.current)
      @tenant.association(:setting).reset
      valuation = Valuation.new(tables: RuleSet.tables(@tenant, today), rules: RuleSet.rules(@tenant), demais_id: RuleSet.demais_id(@tenant), versions: RuleHistory.lookup(@tenant))
      count = 0
      ApplicationRecord.transaction do
        Sql.one("select pg_advisory_xact_lock(2, ?)::text as locked", @tenant.id) # a mesma trava dos segmentos
        BillValuation.where(tenant_id: @tenant.id).delete_all
        Reader.new(@tenant, today: today).each_batch do |batch|
          rows = batch.map do |input|
            result = valuation.call(input)
            [ input.bill_id, @tenant.id, result.principal, result.corrected_principal, result.fine, result.interest, result.fees, result.total, today ]
          end
          save(rows)
          count += rows.size
        end
        # Os títulos de acordo em cobrança têm o saldo devedor com os encargos de atraso dos parâmetros congelados (11, R225, R228).
        rows = Agreements::Valuations.rows(@tenant, today)
        save(rows)
        count += rows.size
      end
      count
    end

    # A tabela de valores atualizados é derivada (recalculada por inteiro a cada vez, sem auditoria por linha): entra por `insert_all!` do modelo.
    def save(rows) = rows.each_slice(5_000) { |slice| BillValuation.insert_all!(slice.map { |row| COLUMNS.zip(row).to_h }, returning: false) }

    # Último recálculo terminado sem falha (a data mostrada em lista, ficha e painel, R173a) e se há um em andamento.
    def self.status(tenant)
      runs = TaskRun.where(tenant_id: tenant.id, name: NAME)
      { last: runs.where.not(status: :running).recent.first,
        calculated_on: BillValuation.where(tenant_id: tenant.id).maximum(:calculated_on),
        running: runs.where(status: :running, started_at: RUNNING_WINDOW.ago..).exists? }
    end
  end
end
