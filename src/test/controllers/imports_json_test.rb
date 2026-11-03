require "test_helper"

# Importações em JSON para a SPA (R10, R56; decisão 0025): lista, envio, página com o resultado, confirmar e o tempo real da situação.
class ImportsJsonTest < ActionDispatch::IntegrationTest
  include CsvHelper
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
  end

  def entrar(usuario) = post(session_path, params: { email_address: usuario.email_address, password: "senha-de-teste-1" })

  def enviar(params) = post(imports_path, params: { import: params }, headers: { "Accept" => "application/json" })

  test "envio, conferência, página e confirmação em JSON" do
    entrar(users(:joana))
    get new_import_path(kind: "portfolio", format: :json)
    nova = response.parsed_body
    assert_equal "Importar carteira", nova["titulo"]
    assert nova["com_modo"]
    assert_includes nova["colunas"].map { |coluna| coluna["nome"] }, "documento"

    enviar(tenant_id: @alfa.id, mode: "incremental")
    assert_response :unprocessable_content
    assert_equal "Escolha o arquivo CSV.", response.parsed_body["mensagem"]

    enviar(tenant_id: @alfa.id, mode: "incremental", file: fixture_file_upload(write_csv([ csv_line ]), "text/csv"))
    import = Import.last
    assert_equal import_path(import), URI(response.parsed_body["destino"]).path
    perform_enqueued_jobs(only: CheckImportJob)

    get import_path(import, format: :json)
    pagina = response.parsed_body
    assert pagina["pode_confirmar"]
    assert_equal "Resultado da conferência", pagina.dig("resultado", "titulo")
    assert_equal "1", pagina.dig("resultado", "pares").find { |par| par["rotulo"] == "Títulos válidos" }["valor"]

    get imports_path(format: :json)
    linha = response.parsed_body["linhas"].first
    assert_equal import.id, linha["id"]
    assert_equal %w[portfolio payments reversals], response.parsed_body["pode_importar"]

    post import_confirmation_path(import), as: :json
    assert_equal "Confirmação iniciada.", response.parsed_body["mensagem"]
  end

  test "o tempo real leva a situação da importação a quem a vê no credor" do
    Rails.cache.clear
    entrar(users(:joana))
    Live::Presence.enter(users(:joana))
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), file: write_csv([ csv_line ]), mode: "incremental", original_name: "carteira.csv")
    assert_enqueued_with(job: LiveBroadcastJob, args: [ "importacoes", [ import.id ], @alfa.id ]) { import.update!(status: "checking") }

    LiveBroadcastJob.perform_now("importacoes", [ import.id ], @alfa.id)
    mensagem = JSON.parse(broadcasts(LiveChannel.broadcasting_for(users(:joana))).last)
    assert_equal import.id, mensagem["registros"].sole["id"]
    assert mensagem["registros"].sole["situacao"]["texto"].present?
  end

  test "operador sem permissão de importação recebe 404 em JSON" do
    entrar(users(:carlos))
    get new_import_path(kind: "portfolio", format: :json)
    assert_response :not_found
  end
end
