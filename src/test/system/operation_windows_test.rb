require "application_system_test_case"

# "Está pra mim?" nas janelas (plano da SPA em EasyUI, critério de saída da fase 6; 14, R313 e R314; decisão 0024): a janela do título e a da divergência
# pedem o mesmo trecho que a página pedia, e o banco responde só com o que está pra operação. O registro de fora vira "não encontrado" dentro da janela,
# sem nada dele na tela, e a aba de onde a janela abriu continua como estava.
class OperationWindowsSystemTest < ApplicationSystemTestCase
  NAO_ENCONTRADO = "Não encontrado, ou você não tem acesso a este registro.".freeze

  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    # Com a permissão das divergências (6), quem decide o que aparece na janela é só o alcance da operação.
    permissions = %w[view_portfolio record_contact_attempts confirm_payments]
    @caio = make_operation_user(@operation, @alfa, profile: operator_profile(@alfa, permissions: permissions).tap { _1.update!(permissions: permissions) })
    @ana = make_customer(@alfa, document: FakeData.cpf(711), name: "Ana Distribuída", contract_code: "OPJ-1")
    @bia = make_customer(@alfa, document: FakeData.cpf(712), name: "Bia da Equipe", contract_code: "OPJ-2")
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: @operation, contract: Contract.find_by!(code: "OPJ-1"), exposure: "all",
                                                             starts_on: Date.current - 3)
    Operations::ReachBuilder.new(@alfa).rebuild
    @nf_ana = @ana.bills.first.number
    @nf_bia = @bia.bills.first.number
  end

  def divergencia(bill)
    ValueDiscrepancy.create!(tenant: @alfa, bill: bill, previous_cents: bill.amount_cents, reported_cents: bill.amount_cents + 1_000, allocated_cents: 0,
                             balance_before_cents: bill.amount_cents, balance_after_cents: bill.amount_cents, effect: "kept", policy: "keep")
  end

  test "a janela do título: o da operação abre; o de fora responde como não encontrado, dentro da janela" do
    entrar_na_casca @caio
    abrir_ficha @ana
    na_aba_interna { click_link @nf_ana }
    assert_selector ".janela-corpo h2", text: "Versões do valor", wait: 15

    visit bill_path(@bia.bills.first) # o endereço direto leva à casca, que abre a janela sobre a aba
    assert_selector ".janela-corpo", text: NAO_ENCONTRADO, wait: 15
    assert_selector ".window .panel-title", text: "Não encontrado"
    assert_no_text @nf_bia
    assert_no_text "Bia da Equipe"
  end

  test "a janela da divergência: a da operação abre; a de fora responde como não encontrada, e a lista não a mostra" do
    minha = divergencia(@ana.bills.first)
    de_fora = divergencia(@bia.bills.first)
    entrar_na_casca @caio
    visitar_lista value_discrepancies_path
    assert_selector "[id='resultado'] .datagrid-row", text: @nf_ana
    assert_no_selector "[id='resultado'] .datagrid-row", text: @nf_bia
    within("[id='resultado']") { click_link @nf_ana }
    assert_selector ".window .panel-title", text: "Divergência do título #{@nf_ana}", wait: 15
    assert_selector ".janela-corpo a[href='#{bill_path(minha.bill)}']"

    visit value_discrepancy_path(de_fora)
    assert_selector ".janela-corpo", text: NAO_ENCONTRADO, wait: 15
    assert_selector ".window .panel-title", text: "Não encontrado"
    assert_no_text @nf_bia
    assert_no_text "Bia da Equipe"
  end
end
