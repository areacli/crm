require "application_system_test_case"

# Diálogos da SPA na ficha (padrões de interface, revisão 38; design system, 7.1 e 7.2; fase 3 do port, decisão 0028): o painel de 480 px com a altura da aba
# e o modal de 400 px, presos à aba; foco no primeiro campo e de volta em quem abriu; Esc, clique na máscara e Cancelar fecham; a validação (422) refaz o
# formulário no diálogo, com o que foi digitado; o sucesso fecha, mostra o aviso e refaz a aba, sem recarregar a página.
class PanelScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321")
    entrar_na_casca
    abrir_ficha(@maria)
  end

  def largura_do_dialogo = page.evaluate_script("Math.round(document.querySelector('.dialogo-conteudo').closest('.window').getBoundingClientRect().width)")

  test "o painel de 480 px tem a altura da aba e o foco no primeiro campo; a máscara cobre só a aba" do
    click_link "Registrar acionamento"
    no_dialogo { assert_field "Canal" }
    assert_selector ".window .panel-title", text: "Registrar acionamento"
    assert_equal 480, largura_do_dialogo
    assert_equal "contact_attempt_channel", page.evaluate_script("document.activeElement.id")
    assert page.evaluate_script("document.querySelector('.aba-raiz > .window-mask') !== null"), "a máscara fica na raiz da aba"
    find("#menu .tree-title", text: "Clientes").click
    assert_selector ".lista .datagrid-row", minimum: 1 # as outras abas continuam usáveis
  end

  test "o modal pequeno tem 400 px e abre pelo menu da barra de página" do
    mais_acoes "Exportar dados"
    no_dialogo { assert_field "Motivo" }
    assert_equal 400, largura_do_dialogo
    assert_equal "export_reason", page.evaluate_script("document.activeElement.id")
  end

  test "Esc fecha e o foco volta ao botão que abriu" do
    find_link("Registrar acionamento").click
    no_dialogo { assert_field "Canal" }
    find_field("Texto (opcional)").send_keys(:escape)
    assert_no_selector ".dialogo-conteudo"
    assert_equal "Registrar acionamento", page.evaluate_script("document.activeElement.textContent.trim()")
  end

  test "o clique na máscara fecha, e Cancelar também; com algo escrito, pergunta antes de descartar" do
    click_link "Registrar acionamento"
    no_dialogo { assert_field "Canal" }
    # Um canto da máscara, longe do diálogo, que fica no meio dela.
    canto = page.evaluate_script("(() => { const r = document.querySelector('.aba-raiz > .window-mask').getBoundingClientRect(); return [r.left + 12, r.bottom - 12] })()")
    page.driver.browser.mouse.click(x: canto[0], y: canto[1])
    assert_no_selector ".dialogo-conteudo"

    click_link "Registrar acionamento"
    no_dialogo { fill_in "Texto (opcional)", with: "rascunho" }
    find_field("Texto (opcional)").send_keys(:escape)
    assert_selector ".window .panel-title", text: "Descartar o que foi escrito?"
    find(".window .l-btn-text", text: "Voltar").click # os botões do `$.messager` são `linkbutton`
    no_dialogo do
      assert_field "Texto (opcional)", with: "rascunho"
      click_button "Cancelar"
    end
    find(".window .l-btn-text", text: "Descartar").click
    assert_no_selector ".dialogo-conteudo"
  end

  test "o 422 refaz o formulário dentro do diálogo, com o erro e o que foi digitado" do
    mais_acoes "Criar contato"
    no_dialogo do
      escolher "Tipo", "E-mail"
      fill_in "Telefone ou e-mail", with: "sem-arroba"
    end
    gravar_dialogo "Criar contato", erro: true
    no_dialogo do
      assert_selector ".aviso", text: /E-mail inválido/
      assert_field "Telefone ou e-mail", with: "sem-arroba"
    end
    assert_equal 1, @maria.contacts.count
  end

  test "o sucesso fecha o diálogo, mostra o aviso e refaz a aba, sem recarregar a página" do
    page.execute_script("window.__sem_recarregar = 1")
    mais_acoes "Criar contato"
    no_dialogo do
      escolher "Tipo", "E-mail"
      assert_no_field "Logradouro" # os campos do endereço só aparecem para o tipo Endereço
      fill_in "Telefone ou e-mail", with: "maria@exemplo.com.br"
    end
    gravar_dialogo "Criar contato"
    assert_aviso "Contato criado"
    assert_selector ".ficha-lateral dd", text: "maria@exemplo.com.br"
    assert_equal 1, page.evaluate_script("window.__sem_recarregar")
  end
end
