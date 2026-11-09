# Auxiliares dos testes de sistema da SPA em EasyUI (decisão 0028): por rótulo visível, porque o `combobox` esconde o campo real e o EasyUI monta o resto por JavaScript.
module SpaTestHelper
  SENHA_DE_TESTE = "senha-de-teste-1".freeze

  def entrar_na_casca(usuario = users(:joana), senha: SENHA_DE_TESTE, endereco: root_path)
    visit endereco
    assert_selector "#entrada-form"
    fill_in "E-mail", with: usuario.email_address
    fill_in "Senha", with: senha
    click_button "Entrar"
    assert_selector "#usuario", text: usuario.name
  end

  # Abre uma aba pelo endereço, como o menu faria (`spa/abas`).
  def abrir_aba(caminho, titulo: nil)
    page.execute_script("import('spa/abas').then((abas) => abas.abrir(arguments[0], { titulo: arguments[1] || undefined }))", caminho, titulo)
  end

  def aba(titulo) = find(".tabs-inner", text: titulo, match: :first).click

  # A lista do `combobox` fica no `body`, fora do formulário: procura-se no documento, mesmo dentro de um `within`.
  # Abre pela seta do campo (o clique no rótulo não reabre a lista depois de uma escolha).
  # O resultado da lista que se refaz no meio (o filtro anterior) pode trocar o nó achado antes do clique: tenta de novo, até três vezes.
  def escolher(rotulo, opcao, tentativas: 3)
    rotulo_do_campo = find("label", text: rotulo, exact_text: true)
    caixa = rotulo_do_campo[:for].present? && first(:xpath, "//*[@id='#{rotulo_do_campo[:for]}']/ancestor::span[contains(concat(' ', @class, ' '), ' textbox ')][1]", minimum: 0)
    caixa ? caixa.find(".combo-arrow").click : rotulo_do_campo.click
    page.document.find(".combobox-item", text: opcao, match: :prefer_exact).click
  rescue Capybara::Cuprite::ObsoleteNode, Ferrum::NodeNotFoundError
    raise if (tentativas -= 1).zero?

    sleep 0.2
    retry
  end

  def linha_da_grade(texto) = find(".datagrid-row", text: texto, match: :first)

  # Espera os pedidos do jQuery terminarem (a busca da lista espera 300 ms depois da última tecla).
  def esperar_os_pedidos(pausa: 0.4)
    sleep pausa
    Timeout.timeout(10) { sleep 0.05 until page.evaluate_script("jQuery.active").zero? }
  end

  # Troca a rota de um pedido antes de ele sair: a resposta vira 404, ou o pedido nem sai (`abortar`).
  def derrubar(padrao, abortar: false)
    acao = abortar ? "xhr.abort()" : 'opcoes.url = "/nao-existe"'
    page.execute_script("const padrao = new RegExp(arguments[0]); jQuery.ajaxPrefilter((opcoes, _o, xhr) => { if (padrao.test(opcoes.url)) { #{acao} } })", padrao)
  end

  # Ficha do cliente (fase 3): abre a aba e espera a aba interna montar a grade dela.
  ABA_INTERNA = ".abas-internas .tabs-panels > .panel:not([style*='display: none'])".freeze

  def abrir_ficha(customer, **params)
    abrir_aba(customer_path(customer, **params))
    assert_selector "#{ABA_INTERNA} .cartao", wait: 10
    esperar_os_pedidos
  end

  # A ficha pelo endereço antigo, vindo de uma página do servidor: ele leva à casca, que abre a aba (`/#/clientes/1`).
  def visitar_ficha(customer, **params)
    visit customer_path(customer, **params)
    assert_selector "#{ABA_INTERNA} .cartao", wait: 15 # a casca carrega o EasyUI e o menu antes de abrir a aba
    esperar_os_pedidos
  end

  # O que está na aba interna escolhida da ficha.
  def na_aba_interna(&) = within(first(ABA_INTERNA, minimum: 1), &)

  def aba_interna(titulo)
    find(".abas-internas .tabs-title", text: titulo, match: :prefer_exact).click
    assert_selector "#{ABA_INTERNA} .cartao", wait: 10
    esperar_os_pedidos
  end

  # Linhas da lista de uma página do servidor na SPA (barra de filtros e o trecho `#resultado`, transformado em grade).
  LINHA_DO_RESULTADO = "[id='resultado'] .datagrid-view2 tr.datagrid-row".freeze

  def assert_linhas_do_resultado(quantidade, **opcoes) = assert_selector(LINHA_DO_RESULTADO, count: quantidade, wait: 10, **opcoes)

  # Lista da SPA pelo endereço antigo (leva à aba na casca), esperando a grade do resultado montar.
  def visitar_lista(caminho)
    visit caminho
    assert_selector "[id='resultado']", wait: 15
    esperar_os_pedidos
  end

  # Menu "⋯" de uma linha da grade e um item dele.
  def menu_da_linha(texto, item)
    linha_da_grade(texto).find(".menu-de-linha").click
    find("[popover]:popover-open :is(.botao, button)", text: item, match: :prefer_exact).click
  end

  # Menu "⋯" da barra da página (as ações que não são a principal).
  def mais_acoes(item)
    find(".aba-raiz .cabecalho-da-pagina .menu-de-linha", match: :first).click
    find("[popover]:popover-open :is(.botao, button)", text: item, match: :prefer_exact).click
  end

  def no_dialogo(&)
    assert_selector ".dialogo-conteudo form.dialogo"
    within(".dialogo-conteudo form.dialogo", &)
  end

  # Grava o diálogo e espera ele fechar; com `erro: true`, espera o formulário refeito (422).
  def gravar_dialogo(botao = nil, erro: false)
    within(".dialogo-conteudo form.dialogo") { botao ? click_button(botao) : find("footer button[type=submit]").click }
    erro ? assert_selector(".dialogo-conteudo form.dialogo .aviso") : assert_no_selector(".dialogo-conteudo")
    esperar_os_pedidos
  end

  # Aviso do canto (`$.messager.show`) que o fim de uma ação mostra.
  def assert_aviso(texto) = assert_selector(".messager-body", text: texto)

  # O teste não tem WebSocket entre o servidor e o navegador: entrega o evento como se o canal o transmitisse.
  def simular_evento(canal, dados)
    page.execute_script("import('spa/tempo-real').then((t) => t.simular(arguments[0], arguments[1]))", canal, dados)
  end
end
