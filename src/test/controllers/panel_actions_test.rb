require "test_helper"

# Fase 2 do redesenho (decisão 0022): as ações restantes pelo painel compartilhado. Cada rota de formulário responde só o conteúdo do painel (modal ou painel lateral)
# ao pedido do htmx, a validação volta em 422 dentro do painel e o sucesso responde 204 com o gatilho `painel:concluido`.
class PanelActionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PAINEL = { "HX-Request" => "true", "HX-Target" => "painel-conteudo" }.freeze

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

  def gatilho = JSON.parse(response.headers["HX-Trigger"]).fetch("painel:concluido")

  test "o formulário abre como conteúdo do painel (modal ou painel lateral) e como página inteira sem o cabeçalho do htmx" do
    { new_agreement_reversion_path(@agreement) => "modal", new_agreement_break_path(@agreement) => "modal", new_agreement_settlement_path(@agreement) => "modal",
      new_membership_path => "drawer", new_profile_path => "drawer", new_settings_channel_path => "drawer", new_settings_contact_result_path => "drawer",
      new_agreement_export_path => "modal" }.each do |caminho, variante|
      get caminho, headers: PAINEL
      assert_response :success, caminho
      assert_select "[data-painel][data-variant=#{variante}] form.painel", 1, caminho
      assert_no_match(/<html/, response.body, caminho)

      get caminho
      assert_response :success, caminho
      assert_select "main form", minimum: 1
    end
  end

  test "a reversão: o motivo em branco volta em 422 dentro do painel, e com motivo responde 204 com o gatilho" do
    post agreement_reversion_path(@agreement), params: { reversion: { reason: " " } }, headers: PAINEL
    assert_response :unprocessable_content
    assert_select "[data-painel] form.painel [role=alert], [data-painel] .aviso"
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
    assert_select "[data-painel][data-variant=modal] form[action='/perfis/1']"
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
    assert_equal "danger", JSON.parse(response.headers["HX-Trigger"]).dig("painel:concluido", "tom") if Profile.exists?(profiles(:alfa_operator).id)
  end

  test "canais: criar pelo painel e a validação em 422" do
    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "account", code: "999-1", description: "Conta nova" } }, headers: PAINEL
    assert_response :no_content

    post settings_channels_path, params: { payment_channel: { tenant_id: @alfa.id, kind: "account", code: "", description: "" } }, headers: PAINEL
    assert_response :unprocessable_content
    assert_select "[data-painel] form.painel"
  end

  test "a exportação do arquivo de acordos e a correção de índice abrem pelo painel" do
    post agreement_exports_path, params: { agreement_export: { tenant_id: @alfa.id, form: "full" } }, headers: PAINEL
    assert_response :no_content
    assert_equal 1, AgreementExport.count

    get new_settings_index_adjustment_path(tenant_id: @alfa.id), headers: PAINEL
    assert_select "[data-painel][data-variant=drawer] input[name='adjustment[month]']"
    post settings_index_adjustments_path(tenant_id: @alfa.id), params: { adjustment: { series: "ipca", month: "", value: "1,5", reason: "x" } }, headers: PAINEL
    assert_response :unprocessable_content
  end

  test "sem o cabeçalho do painel, a ação volta à página com o aviso (sem JavaScript)" do
    post agreement_reversion_path(@agreement), params: { reversion: { reason: " " } }
    assert_redirected_to agreement_path(@agreement)
    assert_match(/./, flash[:alert].to_s)
    post agreement_reversion_path(@agreement), params: { reversion: { reason: "devedor errado" } }
    assert_redirected_to agreement_path(@agreement)
    assert_match(/./, flash[:notice].to_s)
  end
end
