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

    def confirm(import)
      raise ImportRefused, "só uma importação conferida pode ser confirmada" unless import.checked?

      import.update!(status: :confirming, progress_percent: 0)
      ConfirmImportJob.perform_later(import)
      import
    end

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
