# Textos da gestão de acessos: situação de um vínculo e descrição de cada evento do histórico (R42).
module AccessHelper
  def membership_status(membership)
    user = membership.user
    if !user.active? then situacao("Usuário desativado", tom: :danger)
    elsif !membership.active? then situacao("Acesso desativado", tom: :neutral)
    elsif user.temporary_password? then situacao("Senha temporária", tom: :info)
    else situacao("Ativo", tom: :success)
    end
  end

  # O texto do evento, com os dados que ele guarda (perfil, antes e depois...). Nunca há senha nos detalhes.
  def event_description(event)
    details = (event.details || {}).symbolize_keys.transform_values { |value| value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value }
    I18n.t("access_events.#{event.event}", default: event.event.humanize, **details)
  end
end
