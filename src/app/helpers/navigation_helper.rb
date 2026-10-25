# Menu lateral por permissão: o item só aparece para quem tem a permissão em algum credor (MT-4). Só texto, o atual com aria-current.
module NavigationHelper
  def menu_sections
    return @menu if @menu

    user = Current.user
    return [] if user.nil? || user.temporary_password?

    sections = [
      { titulo: nil, itens: [ [ "Resumo", root_path, "view_portfolio", %r{\A/\z} ] ] },
      { titulo: "Carteira", itens: [ [ "Clientes", customers_path, "view_portfolio", %r{\A/clientes} ],
                                     [ "Importar carteira", new_import_path, "upload_imports", %r{\A/importacoes/nova} ],
                                     [ "Importações", imports_path, %w[upload_imports confirm_imports], %r{\A/importacoes(?!/nova)} ] ] },
      { titulo: "Administração", itens: [ [ "Usuários", memberships_path, "manage_users", %r{\A/usuarios} ],
                                          [ "Perfis", profiles_path, "manage_profiles", %r{\A/perfis} ],
                                          [ "Configuração", settings_portfolio_path, "change_settings", %r{\A/configuracao} ] ] }
    ]
    sections.filter_map do |section|
      items = section[:itens].filter_map do |label, path, permissions, pattern|
        next unless Array(permissions).any? { |permission| user.permitted_anywhere?(permission) }

        { rotulo: label, caminho: path, atual: request.path.match?(pattern) }
      end
      section.merge(itens: items) if items.any?
    end
  end

  # Canais do WebSocket que a página assina (um por credor em que o usuário acompanha importações), lidos por `cable.js`.
  def import_cable_channels
    tenant_ids = (Current.user.tenant_ids_with("upload_imports") + Current.user.tenant_ids_with("confirm_imports")).uniq
    tenant_ids.map { |id| { channel: "ImportsChannel", tenant_id: id } }.to_json
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
