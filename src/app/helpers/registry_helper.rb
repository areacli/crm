# Textos do cadastro do cliente na ficha (06): situação, origem, papéis nos contratos e o histórico do cadastro (R116).
module RegistryHelper
  STATUS_TONES = { "valid" => :success, "do_not_disturb" => :warning, "invalid" => :danger }.freeze

  def contact_kind(kind) = t("registry.kinds.#{kind}")

  def contact_status(contact) = situacao(t("registry.statuses.#{contact.status}"), tom: STATUS_TONES.fetch(contact.status))

  def contact_origin(origin) = t("registry.origins.#{origin}")

  # 17, R422 e R423: os nomes dos sistemas do credor, por id, quando ele tem mais de um além do CRM; com um só, nil, e as telas ficam como eram. Uma leitura
  # por credor em cada requisição.
  def system_names(tenant_id)
    @system_names ||= {}
    @system_names.fetch(tenant_id) { @system_names[tenant_id] = SourceSystem.names_if_several(tenant_id) }
  end

  # Origem de uma mudança do cadastro: a tela, ou a carga, com o sistema dela quando o credor tem mais de um (R423).
  def change_origin(change, tenant_id)
    return contact_origin(change.origin) if change.origin.present?

    name = system_names(tenant_id)&.dig(change.source_system_id)
    name ? "carga do sistema #{name}" : "carga"
  end

  # Papéis do cliente num contrato (R124a). Sem responsável financeiro declarado no contrato, os titulares aparecem como responsáveis (MT-16).
  def role_label(row, rows)
    financial_declared = rows.any? { |other| other.roles.include?("financial_responsible") }
    labels = []
    labels << t("registry.roles.holder") if row.roles.include?("holder")
    labels << t("registry.roles.financial_responsible") if row.roles.include?("financial_responsible") || (!financial_declared && row.roles.include?("holder"))
    labels.empty? ? "—" : labels.join(" e ")
  end

  # Uma linha do histórico do cadastro: o que mudou, com os contatos pelo valor que têm hoje.
  def registry_change_text(change, contacts_by_id)
    # 17, R411: o nome que um sistema sem prevalência mandou fica registrado, sem mudar o cadastro.
    return "nome mantido: #{change.before} (#{change.source_system&.name || 'a carga'} informou #{change.after})" if change.event == "name_ignored"
    return "nome: #{change.before} → #{change.after}" if change.subject_type == "customer"

    contact = contacts_by_id[change.subject_id]
    label = contact ? "#{contact_kind(contact.kind).downcase} #{contact.value}" : "contato"
    status = ->(key) { key.present? ? t("registry.statuses.#{key}").downcase : "—" }
    text = change.event == "created" ? "criado (#{status.call(change.after)})" : "#{status.call(change.before)} → #{status.call(change.after)}"
    "#{label}: #{text}#{" — #{change.note}" if change.note.present?}"
  end
end
