module Portfolio
  # Configuração do credor: faixas de atraso (R18) e tratamento do a vencer (R20), com histórico de quem mudou e quando.
  class SettingsService
    # @raise [InvalidBrackets]
    def update_brackets(tenant, input, user)
      new_brackets = AgingBrackets.from(input)
      setting = tenant.setting
      before = setting.aging_brackets.to_json
      setting.update!(aging_brackets: new_brackets.brackets)
      log(tenant, user, "brackets_changed", "aging_brackets", before, new_brackets.brackets.to_json)
    end

    def update_upcoming_display(tenant, display, user)
      setting = tenant.setting
      before = setting.upcoming_display
      setting.update!(upcoming_display: display)
      log(tenant, user, "upcoming_display_changed", "upcoming_display", before, setting.upcoming_display) if before != setting.upcoming_display
    end

    private
      def log(tenant, user, event, field, before, after)
        Change.create!(tenant: tenant, user: user, subject_type: "settings", subject_id: tenant.id, event: event, field: field, before: before, after: after)
      end
  end
end
