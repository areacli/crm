# Menu lateral por permissão: o item só aparece para quem tem a permissão em algum credor (MT-4). Só texto, o atual com aria-current.
module NavigationHelper
  # Abas da configuração (P21): rótulo, rota e a permissão de cada uma. A entrada "Configuração" do menu abre a primeira que o usuário vê.
  SETTINGS_TABS = [
    [ "Dados do credor", :settings_tenant_registry_path, "change_settings" ],
    [ "Carteira", :settings_portfolio_path, "change_settings" ],
    [ "Canais de recebimento", :settings_channels_path, "change_settings" ],
    [ "Políticas de pagamento", :settings_payment_policy_path, "change_financial_policies" ],
    [ "Resultados de acionamento", :settings_contact_results_path, "manage_contact_results" ]
  ].freeze

  # Abas visíveis para o usuário, com o caminho e se é a da página atual.
  def settings_tabs
    SETTINGS_TABS.filter_map do |label, route, permission|
      next unless Current.user.permitted_anywhere?(permission)

      path = public_send(route)
      { rotulo: label, caminho: path, atual: request.path.start_with?(path) }
    end
  end

  def settings_entry_path = settings_tabs.first&.fetch(:caminho) || root_path

  def menu_sections
    return @menu if @menu

    user = Current.user
    return [] if user.nil? || user.temporary_password?

    sections = [
      { titulo: nil, itens: [ [ "Resumo", root_path, "view_portfolio", %r{\A/\z} ] ] },
      { titulo: "Carteira", itens: [ [ "Clientes", customers_path, "view_portfolio", %r{\A/clientes} ],
                                     [ "Acionamentos", contact_attempts_path, "view_portfolio", %r{\A/acionamentos} ],
                                     [ "Importar carteira", new_import_path, "upload_imports", %r{\A/importacoes/nova(?!\?kind=(payments|reversals))} ],
                                     [ "Importar pagamentos", new_import_path(kind: "payments"), "upload_payments", %r{\A/importacoes/nova\?kind=payments} ],
                                     [ "Importar estornos", new_import_path(kind: "reversals"), "upload_payments", %r{\A/importacoes/nova\?kind=reversals} ],
                                     [ discrepancies_label, value_discrepancies_path, "confirm_payments", %r{\A/divergencias-de-valor} ],
                                     [ "Importações", imports_path, ImportPolicy::UPLOAD.values.uniq + ImportPolicy::CONFIRM.values.uniq, %r{\A/importacoes(?!/nova)} ] ] },
      { titulo: "Administração", itens: [ [ "Usuários", memberships_path, "manage_users", %r{\A/usuarios} ],
                                          [ "Perfis", profiles_path, "manage_profiles", %r{\A/perfis} ],
                                          [ "Configuração", settings_entry_path, SETTINGS_TABS.map(&:last), %r{\A/configuracao} ] ] }
    ]
    sections.filter_map do |section|
      items = section[:itens].filter_map do |label, path, permissions, pattern|
        next unless Array(permissions).any? { |permission| user.permitted_anywhere?(permission) }

        { rotulo: label, caminho: path, atual: request.fullpath.match?(pattern) }
      end
      section.merge(itens: items) if items.any?
    end
  end

  # "Divergências de valor" com o número das abertas que a pessoa pode tratar (05, DV3, MT-4): só os credores em que ela confirma pagamentos.
  # Consulta: `value_discrepancies (tenant_id, status, id)`.
  def discrepancies_label
    ids = Current.user.tenant_ids_with("confirm_payments")
    open = ids.any? ? ValueDiscrepancy.where(tenant_id: ids, status: "open").count : 0
    open.positive? ? "Divergências de valor (#{number_br(open)})" : "Divergências de valor"
  end

  # Canais do WebSocket que a página assina (um por credor em que o usuário acompanha importações), lidos por `cable.js`.
  def import_cable_channels
    tenant_ids = (ImportPolicy::UPLOAD.values + ImportPolicy::CONFIRM.values).uniq.flat_map { |permission| Current.user.tenant_ids_with(permission) }.uniq
    tenant_ids.map { |id| { channel: "ImportsChannel", tenant_id: id } }.to_json
  end

  # Canais dos acionamentos: a lista assina um por credor em que o usuário consulta a carteira; a ficha assina o do cliente.
  def contact_cable_channels(tenant_ids) = tenant_ids.map { |id| { channel: "ContactAttemptsChannel", tenant_id: id } }.to_json

  def customer_contact_cable_channels(customer) = [ { channel: "ContactAttemptsChannel", customer_id: customer.id } ].to_json

  # Canais que a página assina, lidos por `cable.js`: os da própria tela (`content_for :cable_channels`) e, para quem está logado e
  # já definiu a senha, o canal de avisos do próprio usuário (o sino).
  def cable_channels
    # `content_for` guarda o JSON com as aspas escapadas para HTML: desfaz antes de ler.
    channels = JSON.parse(CGI.unescapeHTML(content_for(:cable_channels).to_s).presence || "[]")
    channels << { channel: "NoticesChannel" } if authenticated? && !Current.user.temporary_password?
    channels.to_json
  end
end
