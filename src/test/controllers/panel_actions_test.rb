require "test_helper"

# As ações em diálogo (decisão 0028; antes, o painel compartilhado da decisão 0022): cada rota de formulário responde o formulário do diálogo (modal ou lateral)
# ao pedido da SPA, a validação volta em 422 dentro dele e o sucesso responde 204 com o fim de ação no `X-CRM-Evento`.
class PanelActionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PAINEL = SpaRequestsHelper::TRECHO

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, id: "PIX-ENTRADA") ])
    @agreement.reload
    post session_path, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }
  end

  teardown { travel_back }

  def gatilho = evento_da_spa

  test "o formulário abre como diálogo (modal de 400 px ou lateral de 480 px); o endereço como página leva à casca" do
    { new_agreement_reversion_path(@agreement) => "400", new_agreement_break_path(@agreement) => "400", new_agreement_settlement_path(@agreement) => "400",
      new_membership_path => "480", new_settings_channel_path => "480", new_settings_contact_result_path => "480",
      new_agreement_export_path => "400" }.each do |caminho, largura|
      get caminho, headers: PAINEL
      assert_response :success, caminho
      assert_select "form.dialogo[data-largura-do-dialogo='#{largura}']", 1, caminho
      assert_no_match(/<html/, response.body, caminho)

      get caminho
      assert_redirected_to "/##{caminho}"
    end
  end

  test "a reversão: o motivo em branco volta em 422 dentro do painel, e com motivo responde 204 com o gatilho" do
    post agreement_reversion_path(@agreement), params: { reversion: { reason: " " } }, headers: PAINEL
    assert_response :unprocessable_content
    assert_select "form.dialogo .aviso"
    assert_not_predicate @agreement.reload, :reversing?

    post agreement_reversion_path(@agreement), params: { reversion: { reason: "devedor errado" } }, headers: PAINEL
    assert_response :no_content
    assert_equal true, gatilho["atualizar"]
    assert_match(/Reversão/i, gatilho["aviso"].to_s)
    assert_predicate @agreement.reload, :reversing?

    patch agreement_reversion_path(@agreement), headers: PAINEL
    assert_response :no_content
    assert_predicate @agreement.reload, :state_canceled?
  end

  test "a confirmação: o token assinado abre o modal; token adulterado ou destino externo é 404" do
    token = Confirmation.sign(titulo: "Apagar?", mensagem: "Some.", acao: "Apagar", url: "/perfis/1", metodo: :delete, perigoso: true)
    get confirmation_path(token), headers: PAINEL
    assert_response :success
    assert_select "form.dialogo[data-largura-do-dialogo='400'][action='/perfis/1']"
    assert_select "button[data-variant=danger]", text: "Apagar"

    get confirmation_path("#{token}x"), headers: PAINEL
    assert_response :not_found
    get confirmation_path(Confirmation.sign(titulo: "x", mensagem: "x", acao: "x", url: "https://exemplo.com/", metodo: :post, perigoso: false)), headers: PAINEL
    assert_response :not_found
  end

  test "a quebra manual e o cálculo de quitação respondem 204 pelo painel" do
    post agreement_settlement_path(@agreement), params: { settlement: { on_date: Date.current.iso8601 } }, headers: PAINEL
    assert_response :no_content
    assert_equal true, gatilho["atualizar"]

    post agreement_settlement_path(@agreement), params: { settlement: { on_date: "2020-01-01" } }, headers: PAINEL
    assert_response :unprocessable_content
  end

  test "perfis: criar e apagar pelo painel; apagar leva o aviso de erro quando o perfil está em uso" do
    post profiles_path, params: { profile: { tenant_id: @alfa.id, name: "Novo perfil", permissions: [ "", "view_portfolio" ] } }, headers: PAINEL
    assert_response :no_content
    profile = Profile.find_by!(name: "Novo perfil")

    delete profile_path(profile), headers: PAINEL
    assert_response :no_content
    assert_nil Profile.find_by(id: profile.id)

    delete profile_path(profiles(:alfa_operator)), headers: PAINEL
    assert_response :no_content
    assert_equal "danger", evento_da_spa["tom"] if Profile.exists?(profiles(:alfa_operator).id)
  end

  test "canais: criar pelo painel e a validação em 422" do
    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "account", code: "999-1", description: "Conta nova" } }, headers: PAINEL
    assert_response :no_content

    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "account", code: "", description: "" } }, headers: PAINEL
    assert_response :unprocessable_content
    assert_select "form.dialogo"
  end

  test "a exportação do arquivo de acordos e a correção de índice abrem pelo painel" do
    post agreement_exports_path, params: { agreement_export: { tenant_id: @alfa.id, form: "full" } }, headers: PAINEL
    assert_response :no_content
    assert_equal 1, AgreementExport.count

    get new_settings_index_adjustment_path(credor: @alfa.id), headers: PAINEL
    assert_select "form.dialogo[data-largura-do-dialogo='480'] input[name='adjustment[month]']"
    post settings_index_adjustments_path(credor: @alfa.id), params: { adjustment: { series: "ipca", month: "", value: "1,5", reason: "x" } }, headers: PAINEL
    assert_response :unprocessable_content
  end

  test "sem o cabeçalho da SPA, a ação volta ao destino com o aviso" do
    post agreement_reversion_path(@agreement), params: { reversion: { reason: " " } }
    assert_redirected_to agreement_path(@agreement)
    assert_match(/./, flash[:alert].to_s)
    post agreement_reversion_path(@agreement), params: { reversion: { reason: "devedor errado" } }
    assert_redirected_to agreement_path(@agreement)
    assert_match(/./, flash[:notice].to_s)
  end
end
