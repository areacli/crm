# Pedidos dos testes de controlador como a casca da SPA os faz (decisão 0028). Nenhuma tela interna tem página do servidor: os endereços levam à casca
# (`/#/clientes/1`), e os trechos vêm com o cabeçalho `X-CRM-Trecho`.
module SpaRequestsHelper
  TRECHO = { "X-CRM-Trecho" => "1" }.freeze

  # A ficha chega em dois pedidos: o trecho da ficha (cabeçalho, contratos e lateral) e o da aba interna (`X-CRM-Secao`). O auxiliar junta os dois no corpo
  # da resposta, para as asserções valerem para a tela inteira; a recusa (404) fica na primeira resposta.
  def get_ficha(customer, **params)
    get customer_path(customer, **params), headers: TRECHO
    return unless response.successful?

    ficha = response.body
    get customer_path(customer, **params), headers: TRECHO.merge("X-CRM-Secao" => "1")
    response.body = ficha + response.body
  end

  # Lista de clientes: a grade pede a página em JSON (`{ total, rows }`).
  def get_clientes(**params)
    get customers_path(format: :json, **params), headers: TRECHO
    response.parsed_body
  end

  def linhas_de_clientes(**) = get_clientes(**).fetch("rows")

  # Segue o redirecionamento de uma ação pedida sem o cabeçalho da SPA como a casca o pediria: com o cabeçalho do trecho (a página só levaria à casca). As
  # impressões e os downloads, que servem página ou arquivo, como antes.
  def seguir_redirecionamento!
    direto = %r{/termo\z|/exportacao\z|/pdf\z|/qrcode\z|/modelo\z}.match?(URI(response.location).path)
    direto ? follow_redirect! : follow_redirect!(headers: TRECHO.dup)
  end

  # O menu da casca (`menu.json`): os rótulos dos itens, com os dos submenus. O pedido troca a resposta do teste; peça a tela depois.
  def rotulos_do_menu
    get menu_path(format: :json)
    response.parsed_body["grupos"].flat_map { |grupo| grupo["itens"] }.flat_map { |item| [ item["rotulo"], *Array(item["subitens"]).map { |sub| sub["rotulo"] } ] }
  end

  # Os grupos do menu da casca, com os rótulos dos itens de primeiro nível: `{ "Geral" => ["Resumo", ...], ... }`.
  def grupos_do_menu
    get menu_path(format: :json)
    response.parsed_body["grupos"].to_h { |grupo| [ grupo["titulo"], grupo["itens"].map { |item| item["rotulo"] } ] }
  end

  # Um item do menu da casca, com o contador: `{ "rotulo" =>, "caminho" =>, "contador" => }` ou nil.
  def item_do_menu(rotulo)
    get menu_path(format: :json)
    itens = response.parsed_body["grupos"].flat_map { |grupo| grupo["itens"] }
    (itens + itens.flat_map { |item| Array(item["subitens"]) }).find { |item| item["rotulo"] == rotulo }
  end

  # Os rótulos do submenu de um item do menu da casca (Configuração, Operações).
  def submenu_do_menu(rotulo)
    get menu_path(format: :json)
    item = response.parsed_body["grupos"].flat_map { |grupo| grupo["itens"] }.find { |candidato| candidato["rotulo"] == rotulo }
    Array(item&.dig("subitens")).map { |sub| sub["rotulo"] }
  end

  # O fim de uma ação na SPA (204): aviso, atualizar e navegar, no cabeçalho `X-CRM-Evento`.
  def evento_da_spa = JSON.parse(response.headers["X-CRM-Evento"] || "{}")

  # O texto de uma célula da linha (`{ texto: }` nas colunas ricas).
  def celula(linha, campo) = linha[campo].is_a?(Hash) ? linha[campo]["texto"] : linha[campo]
end
