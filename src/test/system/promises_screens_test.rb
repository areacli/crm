require "application_system_test_case"

# Promessas no navegador (10), nas abas da casca: na ficha, o bloco do diálogo de acionamento reage ao resultado e mostra o valor antes de gravar, e a linha
# da promessa aparece na aba Promessas e acordos; a lista de pendentes, a configuração e o resumo.
class PromisesScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
    Tier.catch_all_of(@alfa).update!(promise_max_days: 60)
    PromiseLimit.where(tier: Tier.catch_all_of(@alfa), profile: profiles(:alfa_manager)).update_all(max_days: 60)
  end

  # Data do `datebox` (dd/mm/aaaa), como quem digita no campo; o valor vai ao servidor em aaaa-mm-dd.
  def escolher_data(rotulo, data)
    campo = find_field(rotulo)
    campo.fill_in(with: data.strftime("%d/%m/%Y"))
    campo.send_keys(:tab)
    esperar_os_pedidos
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  def abrir_registro
    entrar_na_casca
    abrir_ficha(@customer, aba: "promessas")
    click_link "Registrar acionamento"
    assert_selector ".dialogo-conteudo form.dialogo"
    esperar_os_pedidos
  end

  def montar_promessa(data)
    no_dialogo do
      escolher "Resultado", "Prometeu pagar"
      esperar_os_pedidos
      assert_selector "#bloco-promessa legend", text: "Registrar promessa"
      escolher "Canal", "Telefone"
      escolher "Contrato da promessa", "CT-1"
      esperar_os_pedidos
      assert_selector "#bloco-promessa input[type=checkbox]", count: 2
      check "NF-1, vence em 15/07/2026, saldo R$ 1.000,00"
      esperar_os_pedidos
      yield if block_given?
      escolher "Meio de pagamento", "Pix"
      esperar_os_pedidos
      escolher_data "Data prometida", data
    end
  end

  test "o diálogo mostra o bloco da promessa e o valor de cada título, e registra a promessa; a ficha mostra a linha" do
    abrir_registro
    assert_no_selector "#bloco-promessa"
    montar_promessa(Date.current + 9) do
      check "NF-2, vence em 15/09/2026, saldo R$ 500,00"
      esperar_os_pedidos
    end
    no_dialogo { assert_selector "#bloco-promessa tfoot td", text: /R\$ \d/ }
    sem_rolagem_horizontal

    gravar_dialogo "Registrar acionamento"
    assert_aviso "Acionamento registrado"
    na_aba_interna do
      linha = linha_da_grade("PRM-000001")
      find(".datagrid-view1 tr.datagrid-row[datagrid-row-index='#{linha['datagrid-row-index']}'] .datagrid-row-expander").click
      assert_selector ".datagrid-row-detail", text: /NF-1 e NF-2/
    end
  end

  test "o diálogo volta com o motivo quando a data passa do prazo máximo" do
    abrir_registro
    montar_promessa(Date.current + 120)
    gravar_dialogo "Registrar acionamento", erro: true
    no_dialogo do
      assert_text "A data prometida vai até"
      assert_checked_field "NF-1, vence em 15/07/2026, saldo R$ 1.000,00"
    end
    assert_equal 0, PaymentPromise.count
  end

  test "a promessa registrada por outro aparece na ficha pelo evento do tempo real, sem recarregar a página" do
    entrar_na_casca
    abrir_ficha(@customer, aba: "promessas")
    na_aba_interna { assert_text "Nenhuma promessa aberta ou pendente." }
    page.execute_script("window.__sem_recarregar = 1")
    register_promise(@customer, [ @nf1 ], user: users(:carlos))
    sleep 1.6 # a aba ignora o evento que chega logo depois de ela mesma se refazer (a rajada da própria gravação)
    simular_evento({ channel: "PromisesChannel", customer_id: @customer.id }, { event: "promises-changed" })
    na_aba_interna { assert_selector ".datagrid-row", text: "PRM-000001", wait: 10 }
    assert_equal 1, page.evaluate_script("window.__sem_recarregar")
  end

  test "pendentes e aprovação, a configuração e o painel nas abas" do
    register_promise(@customer, [ @nf1, @nf2 ], user: users(:carlos), on: Date.current + 45)
    entrar_na_casca
    # Promessas pendentes estão na SPA (fase 4): a lista na aba, e aprovar termina com o aviso e a lista refeita.
    visitar_lista pending_promises_path
    assert_selector ".aba-raiz h1", text: "Promessas pendentes"
    assert_linhas_do_resultado 1
    within("[id='resultado']") { click_button "Aprovar", match: :first }
    assert_aviso "Promessa PRM-000001 aprovada."
    assert_selector "[id='resultado'] .vazio", wait: 10
    visitar_ficha(@customer, aba: "promessas") # o endereço antigo leva à aba na casca
    na_aba_interna { assert_selector ".datagrid-row", text: /Aberta/ }
    menu_da_linha("PRM-000001", "Cancelar promessa")
    no_dialogo { assert_field "Motivo" }
    no_dialogo { click_button "Cancelar" }

    # A configuração está na SPA (fase 7), fora do axe (D7).
    abrir_aba settings_promises_path
    assert_selector ".aba-raiz h1", text: "Promessas e acordos", wait: 10
    assert_selector ".aba-raiz h2", text: /Prazo máximo e alçada/
    sem_rolagem_horizontal
    abrir_aba settings_contact_results_path
    assert_selector ".aba-raiz .datagrid-header", text: "Admite promessa", wait: 10

    visit summary_path # o endereço antigo leva à aba do resumo na casca
    assert_selector ".aba-raiz h2", text: "Promessas", wait: 15
  end
end
