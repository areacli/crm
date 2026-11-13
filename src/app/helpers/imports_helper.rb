# Textos das telas de importação.
module ImportsHelper
  # A coluna "Sistema" da lista de importações (17, R422): a carteira é de um sistema; pagamentos e estornos trazem o sistema por linha e, no credor com
  # mais de um sistema além do CRM, não têm sistema único.
  def import_system(import, multi_system_tenants)
    return import.source_system&.name || "—" if import.portfolio?

    multi_system_tenants.include?(import.tenant_id) ? "vários" : "—"
  end

  # A mudança que uma linha segura da conferência traz (17, R409a).
  def hold_change_text(row)
    identity = "id de cliente #{row.external_customer_id} com outro documento"
    case row.hold_kind
    when "debtor" then "Troca de devedor"
    when "identity" then identity.upcase_first
    else "Troca de devedor e #{identity}"
    end
  end

  # O que o "Confirmar" da importação diz antes de gravar: o efeito do tipo, as mudanças a confirmar (17, R409a) e, no batimento, o que sai, com o
  # nome do sistema (17, R414).
  def import_confirm_message(import, data)
    parts = [ t("imports.confirm_message.#{import.kind}") ]
    return parts.first unless import.portfolio?

    if data.dig(:holds, :count).to_i.positive?
      counts = Portfolio::Holds.new(import).counts
      parts << if counts.total == 1 then "A mudança a confirmar #{counts.confirmed == 1 ? 'será aplicada' : 'fica como está'}."
      else
        "Das #{number_br(counts.total)} mudanças a confirmar, #{number_br(counts.confirmed)} #{counts.confirmed == 1 ? 'será aplicada' : 'serão aplicadas'} e " \
          "#{number_br(counts.unapplied)} #{counts.unapplied == 1 ? 'fica como está' : 'ficam como estão'}."
      end
    end
    if import.full_sync?
      count = data.dig(:to_withdraw, :count).to_i
      parts << "#{count == 1 ? 'Será retirado' : 'Serão retirados'} #{number_br(count)} #{count == 1 ? 'título' : 'títulos'} do #{import.source_system.name}: os que não vieram no arquivo saem da cobrança."
    end
    parts.join(" ")
  end
end
