require "application_system_test_case"

# Importação pela SPA (fase 5 do port, decisão 0028; design system, 7.2): o arquivo vai em `FormData` com o percentual enviado, a importação abre na aba
# dela, e o andamento se refaz pelo tempo real só no trecho do estado, sem recarregar a aba; a recusa volta na tela de envio, com a mensagem.
class ImportsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    entrar_na_casca
  end

  def enviar(arquivo)
    abrir_aba(new_import_path)
    assert_selector ".aba-raiz .filebox", wait: 10
    find(".aba-raiz input.textbox-value[type=file]", visible: :all).attach_file(arquivo, make_visible: true)
    click_button "Enviar e conferir"
  end

  test "o envio abre a importação na aba dela, e o andamento se refaz pelo tempo real sem recarregar a aba" do
    enviar(write_csv([ csv_line ]))
    assert_aviso "Arquivo recebido. A conferência começou."
    assert_selector "#abas .tabs-selected .tabs-title", text: "Importação de", wait: 10
    assert_selector ".aba-raiz #importacao .situacao", text: "Recebida"
    page.execute_script("document.querySelector('#importacao').closest('.aba-raiz').querySelector('.cabecalho-da-pagina').dataset.marca = 'antes'")

    perform_enqueued_jobs(only: CheckImportJob)
    sleep 1.6 # a aba ignora a rajada logo depois de se refazer
    simular_evento({ channel: "ImportsChannel", tenant_id: @alfa.id }, { event: "import-changed" })
    assert_selector ".aba-raiz #importacao .situacao", text: "Conferida, aguardando confirmação", wait: 10
    assert_selector ".aba-raiz .cabecalho-da-pagina[data-marca='antes']" # só o trecho do estado se refez
    assert_text "Nada foi gravado até agora."
  end

  test "a recusa volta na tela de envio, com a mensagem, e o indicador da aba não fica preso" do
    Import.create!(tenant: @alfa, user: users(:joana), kind: :portfolio, mode: :incremental, status: :checked, original_name: "outra.csv", size_bytes: 10)
    enviar(write_csv([ csv_line ]))
    assert_selector ".aba-raiz .aviso[data-tone=danger]", text: "Há uma importação em andamento.", wait: 10
    assert_selector ".aba-raiz .filebox" # a tela refeita, pronta para outro envio
    assert_no_selector "#abas .tabs-title .girando"
  end
end
