module Portfolio
  # Ciclo da importação de carteira: enviar, conferir, confirmar ou descartar.
  class ImportService
    # Envia o arquivo (caminho ou upload) e enfileira a conferência. A carteira entra por um sistema do credor (17, R400): o escolhido no envio
    # ou, sem escolha, o Planilha.
    # @raise [ImportRefused] quando já há uma importação em andamento no credor (R10; o índice parcial do banco é quem garante), quando o
    #   sistema está pausado (R398) ou quando o credor não tem sistema ativo (R400).
    def start(tenant:, user:, file:, mode:, original_name: nil, kind: "portfolio", source_system: nil)
      system = receiving_system(tenant, source_system) if kind.to_s == "portfolio"
      name = "#{SecureRandom.uuid}.csv"
      relative = File.join("imports", name)
      FileUtils.mkdir_p(Rails.root.join("storage", "imports"))
      source = file.respond_to?(:tempfile) ? file.tempfile.path : file.to_s
      original_name ||= file.respond_to?(:original_filename) ? file.original_filename : File.basename(source)
      FileUtils.cp(source, Rails.root.join("storage", relative))
      begin
        import = Import.create!(tenant: tenant, user: user, kind: kind, mode: mode, status: :received, original_name: original_name,
                                source_system: system, stored_path: relative, size_bytes: File.size(Rails.root.join("storage", relative)))
      rescue ActiveRecord::RecordNotUnique
        FileUtils.rm_f(Rails.root.join("storage", relative))
        raise ImportRefused, "há uma importação em andamento"
      end
      CheckImportJob.perform_later(import)
      import
    end

    # O sistema que recebe a carga: nenhum ativo recusa o envio, e o pausado não recebe importação nova (a que está em andamento termina).
    def receiving_system(tenant, chosen)
      systems = SourceSystem.where(tenant_id: tenant.id).receiving.to_a
      raise ImportRefused, "nenhum sistema ativo" if systems.none?(&:active?)

      system = chosen || systems.find(&:role_default?)
      raise ImportRefused, "o sistema escolhido não é deste credor" unless systems.include?(system)
      raise ImportRefused, "o sistema #{system.name} está pausado" if system.paused?

      system
    end
    private :receiving_system

    def confirm(import, by: nil)
      raise ImportRefused, "só uma importação conferida pode ser confirmada" unless import.checked?
      recheck_if_policy_changed(import)

      ApplicationRecord.transaction do
        import.update!(status: :confirming, progress_percent: 0, confirmed_by: by, summary: settle_holds(import))
      end
      ConfirmImportJob.perform_later(import)
      import
    end

    # 17, R409a: a mudança que ficou sem confirmação não é aplicada. A linha dela sai das válidas antes da gravação e vai ao resultado; o resumo
    # passa a dizer quantas mudanças serão aplicadas e quantas não. Só há o que fazer quando a conferência achou linha segura.
    def settle_holds(import)
      data = import.summary_data
      return import.summary unless import.portfolio? && data.dig(:holds, :count).to_i.positive?

      result = Holds.new(import).settle
      import.summary.merge("valid" => data[:valid].to_i - result[:unapplied], "holds" => import.summary.fetch("holds").merge(result.stringify_keys))
    end
    private :settle_holds

    # Política trocada entre a conferência e a confirmação (05, casos de exceção): a confirmação usa a política da hora, então a conferência é
    # refeita (o arquivo continua guardado) e a confirmação é recusada até a pessoa ver o novo efeito.
    def recheck_if_policy_changed(import)
      return unless import.portfolio?

      setting = import.tenant.setting
      data = import.summary_data
      changed = %i[discrepancy_policy correction_policy].select { |policy| data[policy].present? && data[policy] != setting.public_send(policy) }
      return if changed.empty?

      import.update!(status: :received, progress_percent: 0, summary: nil)
      CheckImportJob.perform_later(import)
      raise ImportRefused, "a política de #{changed.first == :correction_policy ? 'correção na tela ou carga' : 'divergência'} mudou; a conferência foi refeita, confira de novo"
    end
    private :recheck_if_policy_changed

    def discard(import)
      raise ImportRefused, "só uma importação conferida pode ser descartada" unless import.checked?

      [ ImportRow, ImportContact, PaymentRow ].each { |model| model.where(import_id: import.id).delete_all }
      FileUtils.rm_f(import.file_path)
      import.update!(status: :discarded, finished_at: Time.current)
      import
    end
  end
end
