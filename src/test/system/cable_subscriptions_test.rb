require "application_system_test_case"

# O htmx troca o corpo da página (`hx-boost`) sem recarregar o <head>, onde está a lista de canais do WebSocket: depois do login e de cada link, as
# assinaturas têm de acompanhar a página nova (achado da V5 do marco B: o sino ficava sem assinatura depois de entrar).
class CableSubscriptionsSystemTest < ApplicationSystemTestCase
  def canais = page.evaluate_script("window.cable.canais.map((c) => c.channel)")

  test "depois do login o sino assina o canal de avisos, e cada página assina o que pede" do
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
    assert_equal [ "NoticesChannel" ], canais

    click_link "Acionamentos"
    assert_selector "h1", text: "Acionamentos"
    assert_includes canais, "ContactAttemptsChannel"
    assert_includes canais, "NoticesChannel"

    click_link "Resumo"
    assert_selector "h1", text: "Resumo da carteira"
    assert_equal [ "NoticesChannel" ], canais
  end
end
