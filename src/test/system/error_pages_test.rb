require "application_system_test_case"

# Páginas de erro no navegador: passam no axe, não rolam na horizontal e têm o botão de volta; o aviso de erro de pedido do htmx aparece.
class ErrorPagesSystemTest < ApplicationSystemTestCase
  [ 404, 422, 500, 503 ].each do |status|
    test "a página #{status} passa no axe e não rola na horizontal" do
      [ 1440, 390 ].each do |largura|
        page.driver.resize(largura, 800)
        visit "/#{status}"
        assert_selector "h1"
        assert_link "Ir para o início"
        assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
      end
      assert_acessivel
    end
  end
end
