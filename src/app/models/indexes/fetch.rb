module Indexes
  # Busca diária (e manual) dos índices no Banco Central (R142 a R144). Cada série é validada inteira antes de gravar: resposta inválida
  # (texto no lugar de número, mês repetido) descarta a série naquela execução e a falha fica registrada com a série e o motivo. A execução
  # vira um `TaskRun` global (O8). Com falha, levanta `Failed` no fim, para o job tentar de novo; nada já gravado é apagado.
  class Fetch
    NAME = "index_fetch"
    RUNNING_WINDOW = 30.minutes
    VALUE_FORMAT = /\A-?\d{1,5}(\.\d{1,6})?\z/
    DATE_FORMAT = %r{\A\d{2}/\d{2}/\d{4}\z}

    class Failed < StandardError; end

    def initialize(client: Indexes.client) = @client = client

    def self.running? = TaskRun.where(tenant_id: nil, name: NAME, status: "running", started_at: RUNNING_WINDOW.ago..).exists?

    def call(today: Date.current)
      if self.class.running?
        return TaskRun.create!(name: NAME, status: :skipped, started_at: Time.current, finished_at: Time.current, note: I18n.t("indexes.run.already_running")).tap { Broadcast.changed }
      end

      run = TaskRun.create!(name: NAME, started_at: Time.current)
      written = revised = 0
      problems = []
      IndexRate::SERIES.each do |series|
        added, changed = fetch_series(series, today)
        written += added
        revised += changed
      rescue SourceError => error
        problems << "#{IndexRate.label(series)}: #{error.message}"
      end
      note = problems.any? ? problems.join("; ") : I18n.t("indexes.run.summary", new: written, revised: revised)
      run.update!(status: problems.empty? ? :succeeded : :failed, finished_at: Time.current, processed: written + revised, failed: problems.size,
                  error_kind: problems.any? ? "SourceError" : nil, note: note.truncate(300))
      raise Failed, note if problems.any?

      run
    rescue Failed
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true)
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize, note: I18n.t("indexes.run.unexpected"))
      raise Failed, error.class.name
    ensure
      Broadcast.changed
    end

    private
      # Sem mês trazido pelo Banco Central a busca começa em janeiro de 2000 (DS2); depois, nos últimos 3 meses a partir do último trazido.
      def fetch_series(series, today)
        last = IndexRate.where(series: series).maximum(:month)
        from = last ? [ last - 2.months, today.beginning_of_month - 3.months ].min.beginning_of_month : IndexRate::FIRST_MONTH
        rows = validate(@client.series(IndexRate::CODES.fetch(series), from: from, to: today.end_of_month))
        current = today.beginning_of_month
        known = IndexRate.where(series: series, month: rows.map(&:first)).pluck(:month, :value, :partial).to_h { |m, v, p| [ m, [ v, p ] ] }
        added = rows.count { |month, _| !known.key?(month) }
        revised = rows.count { |month, value| known[month] && (known[month][0] != value || known[month][1] != partial?(series, month, current)) }
        now = Time.current
        # O mês corrente nunca é gravado como mês fechado (R143), exceto a taxa legal, definitiva desde a divulgação (09, R162); o fechado
        # sobrescreve o parcial.
        IndexRate.upsert_all(rows.map { |month, value| { series: series, month: month, value: value, partial: partial?(series, month, current), fetched_at: now } }, unique_by: %i[series month]) if rows.any?
        [ added, revised ]
      end

      def partial?(series, month, current) = series != "legal" && month >= current

      def validate(payload)
        raise SourceError, I18n.t("indexes.errors.invalid") unless payload.is_a?(Array)

        rows = payload.map do |item|
          date = item.is_a?(Hash) ? item["data"].to_s : ""
          value = item.is_a?(Hash) ? item["valor"].to_s.strip : ""
          raise SourceError, I18n.t("indexes.errors.invalid") unless date.match?(DATE_FORMAT) && value.match?(VALUE_FORMAT)

          [ Date.strptime(date, "%d/%m/%Y").beginning_of_month, BigDecimal(value) ]
        rescue Date::Error
          raise SourceError, I18n.t("indexes.errors.invalid")
        end
        raise SourceError, I18n.t("indexes.errors.invalid") if rows.map(&:first).uniq.size != rows.size

        rows
      end
  end
end
