require "application_system_test_case"

# Acionamentos no navegador, nas abas da casca: na ficha, o diálogo que reage ao resultado; a lista, o resumo e os resultados.
class ContactAttemptsScreensSystemTest < ApplicationSystemTestCase
  include SpaTestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321")
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    ContractCustomer.where(customer: @maria).update_all(roles: %w[holder financial_responsible])
    ContractCustomer.where(customer: pedro).update_all(roles: %w[holder])
    @pedro = pedro
    insert_attempt(@maria, user: users(:carlos), result: result_of(@alfa, :negotiating), text: "Quer parcelar em três vezes.\nRetornar na sexta.", contacted_at: 2.hours.ago)
    insert_attempt(@maria, user: users(:joana), result: result_of(@alfa, :voicemail), channel: "whatsapp", contacted_at: 5.hours.ago)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def abrir_registro
    click_link "Registrar acionamento"
    assert_selector ".dialogo-conteudo form.dialogo"
    esperar_os_pedidos
  end

  def ficha(customer)
    entrar_na_casca
    abrir_ficha(customer, aba: "acionamentos")
  end

  test "ficha com acionamentos e o diálogo de registro; a lista e os resultados nas abas, e o resumo" do
    ficha(@maria)
    na_aba_interna do
      assert_selector "h2", text: "Acionamentos"
      assert_selector ".datagrid-row", text: "Quer parcelar em três vezes."
    end
    assert_no_selector "form.dialogo" # nenhum formulário aberto na ficha
    abrir_registro
    no_dialogo { click_button "Cancelar" }
    assert_no_selector ".dialogo-conteudo"

    # A lista está na SPA (fase 4): o endereço antigo leva à aba, com a grade do resultado.
    visitar_lista contact_attempts_path
    assert_selector ".aba-raiz h1", text: "Acionamentos"
    assert_linhas_do_resultado 2

    visit summary_path # o endereço antigo leva à aba do resumo na casca
    assert_selector ".aba-raiz h2", text: "Acionamentos", wait: 15

    # Os resultados estão na SPA (fase 7), fora do axe (D7): criar e editar em diálogos.
    visit settings_contact_results_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Resultados de acionamento", wait: 15
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar resultado").click
    no_dialogo { assert_field "Nome" }
    send_keys :escape
    menu_da_linha("Caixa postal", "Editar")
    no_dialogo { assert_field "Nome", with: "Caixa postal" }
  end

  test "o campo de retorno aparece conforme o resultado e o registro entra no histórico sem recarregar a página" do
    ficha(@pedro)
    page.execute_script("window.__sem_recarregar = 1")
    abrir_registro
    no_dialogo do
      escolher "Canal", "Telefone"
      escolher "Resultado", "Pediu para retornar depois"
      assert_field "Retorno combinado"

      escolher "Resultado", "Número ou endereço inexistente"
      assert_no_field "Retorno combinado"

      escolher "Resultado", "Negociação em andamento"
      assert_field "Retorno combinado (opcional)"

      escolher "Contrato (opcional)", "CT-1"
      assert_text "O responsável financeiro deste contrato é Maria Souza"
      fill_in "Texto (opcional)", with: "Pediu o boleto\npor e-mail"
      fill_in "Contato usado (opcional)", with: "(11) 3333-4444"
    end
    gravar_dialogo "Registrar acionamento"

    assert_aviso "Acionamento registrado."
    assert_equal 1, page.evaluate_script("window.__sem_recarregar")
    na_aba_interna do
      linha = linha_da_grade("Negociação em andamento")
      find(".datagrid-view1 tr.datagrid-row[datagrid-row-index='#{linha['datagrid-row-index']}'] .datagrid-row-expander").click
      assert_selector ".datagrid-row-detail", text: "(11) 3333-4444"
      assert_selector ".datagrid-row-detail", text: "Contrato CT-1"
      assert_selector ".datagrid-row-detail", text: "Pediu o boleto"
    end
    assert_equal 1, @pedro.contact_attempts.count
  end

  test "resultado que exige retorno sem a data: o servidor recusa e o formulário volta preenchido no diálogo" do
    ficha(@pedro)
    abrir_registro
    no_dialogo do
      escolher "Canal", "Telefone"
      escolher "Resultado", "Pediu para retornar depois"
      assert_field "Retorno combinado"
      fill_in "Texto (opcional)", with: "texto que fica"
    end
    gravar_dialogo "Registrar acionamento", erro: true
    no_dialogo do
      assert_text "Este resultado exige data de retorno."
      assert_equal "texto que fica", find_field("Texto (opcional)").value
    end
    assert_equal 0, @pedro.contact_attempts.count
  end

  test "a lista pelo filtro por operador e canal" do
    entrar_na_casca
    visitar_lista contact_attempts_path
    assert_linhas_do_resultado 2
    # Os filtros refazem só o trecho do resultado (`spa/lista`), e o filtro entra no endereço da aba.
    escolher "Operador", "Carlos Lima"
    assert_linhas_do_resultado 1
    assert_includes page.evaluate_script("location.hash"), "operador=#{users(:carlos).id}"
    escolher "Operador", "Todos"
    escolher "Canal", "WhatsApp"
    assert_linhas_do_resultado 1, text: "Caixa postal"
  end
end
