# Menu lateral por permissão: o item só aparece para quem tem a permissão em algum credor (MT-4). Só texto, o atual com aria-current.
module NavigationHelper
  # Abas da configuração (P21): rótulo, rota e a permissão de cada uma. A entrada "Configuração" do menu abre a primeira que o usuário vê.
  SETTINGS_TABS = [
    [ "Dados do credor", :settings_tenant_registry_path, "change_settings" ],
    [ "Carteira", :settings_portfolio_path, "change_settings" ],
    [ "Canais de recebimento", :settings_channels_path, "change_settings" ],
    [ "Políticas de pagamento", :settings_payment_policy_path, "change_financial_policies" ],
    [ "Contas de pagamento", :settings_payment_accounts_path, "change_financial_policies" ],
    [ "Segmentos e encargos", :settings_segments_path, %w[change_settings change_financial_policies] ],
    [ "Promessas e acordos", :settings_promises_path, "change_financial_policies" ],
    [ "Índices", :settings_indexes_path, %w[change_settings change_financial_policies] ],
    [ "Resultados de acionamento", :settings_contact_results_path, "manage_contact_results" ]
  ].freeze

  # Abas visíveis para o usuário, com o caminho e se é a da página atual.
  def settings_tabs
    SETTINGS_TABS.filter_map do |label, route, permission|
      next unless Array(permission).any? { |name| Current.user.permitted_anywhere?(name) }

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
                                     [ "Divergências de valor", value_discrepancies_path, "confirm_payments", %r{\A/divergencias-de-valor}, discrepancies_count ],
                                     [ "Importações", imports_path, ImportPolicy::UPLOAD.values.uniq + ImportPolicy::CONFIRM.values.uniq, %r{\A/importacoes(?!/nova)} ] ] },
      { titulo: "Cobrança", itens: [ [ "Acordos", agreements_path, "negotiate_agreements", %r{\A/acordos(?!/pendentes)} ],
                                     *pending_promises_items,
                                     *pending_agreements_items ] },
      { titulo: "Administração", itens: [ [ "Usuários", memberships_path, "manage_users", %r{\A/usuarios} ],
                                          [ "Guarda de dados", data_retention_path, "handle_data_subject_rights", %r{\A/guarda-de-dados} ],
                                          [ "Perfis", profiles_path, "manage_profiles", %r{\A/perfis} ],
                                          [ "Configuração", settings_entry_path, SETTINGS_TABS.flat_map(&:last), %r{\A/configuracao} ] ] }
    ]
    sections.filter_map do |section|
      items = section[:itens].filter_map do |label, path, permissions, pattern, count|
        next unless Array(permissions).any? { |permission| user.permitted_anywhere?(permission) }

        { rotulo: label, caminho: path, atual: request.fullpath.match?(pattern), contador: (count if count.to_i.positive?) }
      end
      section.merge(itens: items) if items.any?
    end
  end

  # Contador de "Divergências de valor" (selo do menu): as abertas que a pessoa pode tratar (05, DV3, MT-4), só dos credores em que ela confirma pagamentos.
  # Consulta: `value_discrepancies (tenant_id, status, id)`.
  def discrepancies_count
    ids = Current.user.tenant_ids_with("confirm_payments")
    ids.any? ? ValueDiscrepancy.where(tenant_id: ids, status: "open").count : 0
  end

  # "Promessas pendentes" com o selo das que a pessoa pode aprovar (10, R204): só as dos credores em que ela tem a permissão e a alçada.
  def pending_promises_items
    open = Promises::Pending.for(Current.user).count
    open.positive? ? [ [ "Promessas pendentes", pending_promises_path, "record_contact_attempts", %r{\A/promessas/pendentes}, open ] ] : []
  end

  # "Acordos pendentes" com o selo das propostas que a pessoa pode aprovar (11, R216, R243): só as dos credores em que ela tem a permissão e os limites.
  def pending_agreements_items
    open = Agreements::Pending.for(Current.user).count
    open.positive? ? [ [ "Acordos pendentes", pending_agreements_path, "negotiate_agreements", %r{\A/acordos/pendentes}, open ] ] : []
  end

  # Canais do WebSocket que a página assina (um por credor em que o usuário acompanha importações), lidos por `cable.js`.
  def import_cable_channels
    tenant_ids = (ImportPolicy::UPLOAD.values + ImportPolicy::CONFIRM.values).uniq.flat_map { |permission| Current.user.tenant_ids_with(permission) }.uniq
    tenant_ids.map { |id| { channel: "ImportsChannel", tenant_id: id } }.to_json
  end

  # Canais dos acionamentos: a lista assina um por credor em que o usuário consulta a carteira; a ficha assina o do cliente.
  def contact_cable_channels(tenant_ids) = tenant_ids.map { |id| { channel: "ContactAttemptsChannel", tenant_id: id } }.to_json

  # A ficha assina os acionamentos e as promessas do cliente (10, R203).
  def customer_contact_cable_channels(customer)
    channels = [ { channel: "ContactAttemptsChannel", customer_id: customer.id }, { channel: "PromisesChannel", customer_id: customer.id } ]
    channels << { channel: "AgreementsChannel", customer_id: customer.id } if AgreementPolicy.new(Current.user, Agreement.new(tenant: customer.tenant)).watch?
    channels.to_json
  end

  # Canais que a página assina, lidos por `cable.js`: os da própria tela (`content_for :cable_channels`) e, para quem está logado e
  # já definiu a senha, o canal de avisos do próprio usuário (o sino).
  def cable_channels
    # `content_for` guarda o JSON com as aspas escapadas para HTML: desfaz antes de ler.
    channels = JSON.parse(CGI.unescapeHTML(content_for(:cable_channels).to_s).presence || "[]")
    channels << { channel: "NoticesChannel" } if authenticated? && !Current.user.temporary_password?
    channels.to_json
  end
end
