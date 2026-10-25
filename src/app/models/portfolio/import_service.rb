module Portfolio
  # Ciclo da importação de carteira: enviar, conferir, confirmar ou descartar.
  class ImportService
    # Envia o arquivo (caminho ou upload) e enfileira a conferência.
    # @raise [ImportRefused] quando já há uma importação em andamento no credor (R10); o índice parcial do banco é quem garante.
    def start(tenant:, user:, file:, mode:, original_name: nil, kind: "portfolio")
      name = "#{SecureRandom.uuid}.csv"
      relative = File.join("imports", name)
      FileUtils.mkdir_p(Rails.root.join("storage", "imports"))
      source = file.respond_to?(:tempfile) ? file.tempfile.path : file.to_s
      original_name ||= file.respond_to?(:original_filename) ? file.original_filename : File.basename(source)
      FileUtils.cp(source, Rails.root.join("storage", relative))
      begin
        import = Import.create!(tenant: tenant, user: user, kind: kind, mode: mode, status: :received, original_name: original_name,
                                stored_path: relative, size_bytes: File.size(Rails.root.join("storage", relative)))
      rescue ActiveRecord::RecordNotUnique
        FileUtils.rm_f(Rails.root.join("storage", relative))
        raise ImportRefused, "há uma importação em andamento"
      end
      CheckImportJob.perform_later(import)
      import
    end

    def confirm(import, by: nil)
      raise ImportRefused, "só uma importação conferida pode ser confirmada" unless import.checked?
      recheck_if_policy_changed(import)

      import.update!(status: :confirming, progress_percent: 0, confirmed_by: by)
      ConfirmImportJob.perform_later(import)
      import
    end

    # Política trocada entre a conferência e a confirmação (05, casos de exceção): a confirmação usa a política da hora, então a conferência é
    # refeita (o arquivo continua guardado) e a confirmação é recusada até a pessoa ver o novo efeito.
    def recheck_if_policy_changed(import)
      return unless import.portfolio?

      checked_with = import.summary_data[:discrepancy_policy]
      return if checked_with.nil? || checked_with == import.tenant.setting.discrepancy_policy

      import.update!(status: :received, progress_percent: 0, summary: nil)
      CheckImportJob.perform_later(import)
      raise ImportRefused, "a política de divergência mudou; a conferência foi refeita, confira de novo"
    end
    private :recheck_if_policy_changed

    def discard(import)
      raise ImportRefused, "só uma importação conferida pode ser descartada" unless import.checked?

      Sql.run("delete from import_rows where import_id = ?", import.id)
      Sql.run("delete from payment_rows where import_id = ?", import.id)
      FileUtils.rm_f(import.file_path)
      import.update!(status: :discarded, finished_at: Time.current)
      import
    end
  end
end
