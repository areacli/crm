module Demo
  # Recriação da demonstração: apaga os dados dos credores (e os arquivos guardados), mantém os usuários públicos e as tabelas globais, e recria tudo
  # (`Demo::Dataset`). Recusa fora do modo de demonstração. Registra a execução em `TaskRun` e, se falhar, deixa o erro registrado sem apagar de novo.
  class Reset
    NAME = "demo_reset"
    # Ficam: os usuários e as sessões (quem está logado continua logado), o calendário global e o controle do banco.
    KEEP = %w[users sessions municipalities holidays schema_migrations ar_internal_metadata].freeze

    class Refused < StandardError; end

    def call(log: nil)
      raise Refused, "O modo de demonstração não está ligado (CRM_DEMO)." unless Demo.enabled?

      run = TaskRun.create!(name: NAME, started_at: Time.current)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wipe
      alpha, beta = Dataset.new(log: log).call
      run.update!(status: :succeeded, finished_at: Time.current, processed: Customer.count,
                  note: "#{alpha.name} e #{beta.name} recriados em #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round} s")
      run
    rescue Refused
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true)
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize, note: "A recriação falhou; os dados ficaram como estavam ou incompletos.")
      raise
    end

    def wipe
      remove_files
      connection = ActiveRecord::Base.connection
      connection.truncate_tables(*(connection.tables - KEEP))
      Rails.cache.clear
    end

    private
      # Os arquivos guardados (das importações e do Active Storage) saem do disco junto, um a um pelo que o banco conhece: nada além disso é tocado
      # (em teste, outros processos usam o mesmo diretório ao mesmo tempo).
      def remove_files
        Import.where.not(stored_path: nil).pluck(:stored_path).each { |path| FileUtils.rm_f(Rails.root.join("storage", path)) }
        ActiveStorage::Blob.find_each { |blob| blob.service.delete(blob.key) }
      end
  end
end
