module Portfolio
  # Importação presa (especificação 01, revisão 7, domínio P5): recebida, em conferência ou em confirmação sem nenhum avanço de progresso há mais de 30 minutos
  # passa a "falhou", com o motivo "tempo-limite", libera o credor e avisa no sino quem enviou (e quem confirmou). O avanço é a última gravação da importação
  # (`updated_at`), que cada lote e cada etapa renovam; a conferência esperando o gestor não conta, pois ninguém a está processando. Consulta: `imports (tenant_id,
  # status)`, uma varredura das importações em andamento (poucas).
  class StaleImports
    TIMEOUT = 30.minutes
    FAILURE = "tempo-limite".freeze

    def call(now: Time.current)
      stale = Import.where(status: %w[received checking confirming]).where(updated_at: ...(now - TIMEOUT)).includes(:user, :confirmed_by).to_a
      stale.each { |import| fail!(import) }
      stale.size
    end

    private
      def fail!(import)
        # A preparação da leitura some; o que os lotes já gravaram fica (idempotente: enviar o mesmo arquivo de novo conclui).
        [ ImportRow, ImportContact, PaymentRow ].each { |model| model.where(import_id: import.id).delete_all }
        import.update!(status: :failed, failure_reason: FAILURE, finished_at: Time.current, progress_label: nil)
        FileUtils.rm_f(import.file_path) if import.stored_path
        [ import.user, import.confirmed_by ].compact.uniq.each do |user|
          Notice.create!(user: user, kind: "import_stalled", data: { tenant_name: import.tenant.name, file_name: import.original_name })
        end
      end
  end
end
