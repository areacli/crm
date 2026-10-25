require "test_helper"

# Leitura autenticada do instrumento (12, R275): PDF, QR Code e dados em JSON, com a permissão do credor (V10) e sem endereço de fornecedor.
class PaymentInstrumentsScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @customer = make_customer(@alfa)
    @boleto = issue(@alfa, @customer, "boleto")
    @pix = issue(@alfa, @customer, "pix")
  end

  def issue(tenant, customer, kind)
    make_account(tenant, modality: kind, environment: "production", config: { "connection_result" => "ok", "pix_key" => "p@a.com" }, nickname: "#{kind} #{tenant.id}") unless tenant.payment_accounts.exists?(modality: kind)
    instrument = Payments::Issuer.new.request(tenant: tenant, kind: kind, amount_cents: 99_900, customer: customer, due_on: Date.current + 10)
    perform_enqueued_jobs { IssueInstrumentJob.perform_now(instrument.id) }
    instrument.reload
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "sem sessão, nada é servido" do
    get payment_instrument_pdf_path(@boleto)
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "quem consulta a carteira do credor baixa o PDF com Cache-Control private, no-store e sem redirecionar (R275, R279)" do
    entrar(users(:carlos))
    get payment_instrument_pdf_path(@boleto)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Cache-Control"], "private"
    assert_nil response.headers["Location"]
    assert_equal @boleto.boleto_pdf.download, response.body.b
    assert_match(/inline/, response.headers["Content-Disposition"])
  end

  test "o QR Code do Pix sai como PNG; pedir o PDF de um Pix ou o QR de um boleto responde 404" do
    entrar(users(:joana))
    get payment_instrument_qr_code_path(@pix)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal @pix.pix_qr_png.download, response.body.b
    get payment_instrument_pdf_path(@pix)
    assert_response :not_found
    get payment_instrument_qr_code_path(@boleto)
    assert_response :not_found
  end

  test "os dados em texto: linha digitável e copia e cola, sem dados do pagador nem endereço de fornecedor" do
    entrar(users(:joana))
    get payment_instrument_path(@boleto)
    assert_response :success
    data = response.parsed_body
    assert_equal [ "boleto", "active", 99_900 ], data.values_at("kind", "state", "amount_cents")
    assert_equal @boleto.digitable_line, data["digitable_line"]
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not_includes response.body, "52998224725"
    assert_not_includes response.body, "Maria"
    get payment_instrument_path(@pix)
    assert_equal @pix.copy_paste, response.parsed_body["copy_paste"]
  end

  test "instrumento de outro credor responde 404 e o acesso recusado é registrado com o credor dele (V10)" do
    beta_customer = make_customer(@beta, document: PaymentsHelper::JOAO, name: "João")
    beta_boleto = issue(@beta, beta_customer, "boleto")
    entrar(users(:joana))
    [ payment_instrument_path(beta_boleto), payment_instrument_pdf_path(beta_boleto), payment_instrument_qr_code_path(beta_boleto) ].each do |path|
      get path
      assert_response :not_found
    end
    assert_equal 3, AccessEvent.where(event: "access_denied", tenant_id: @beta.id).count
  end

  test "usuário só de outro credor responde 404 registrado em todas as rotas de leitura" do
    entrar(make_user(@beta, []))
    get payment_instrument_pdf_path(@boleto)
    assert_response :not_found
    assert_equal @alfa.id, AccessEvent.where(event: "access_denied").last.tenant_id
  end

  test "instrumento que não está entregável (falho, cancelado, emitindo) responde 404" do
    entrar(users(:joana))
    @boleto.update_columns(state: "canceled")
    get payment_instrument_pdf_path(@boleto)
    assert_response :not_found
    get payment_instrument_path(@boleto)
    assert_response :not_found
  end

  test "arquivo adulterado no disco (SHA-256 diferente) não é servido" do
    entrar(users(:joana))
    @boleto.update_columns(boleto_pdf_sha256: "0" * 64)
    get payment_instrument_pdf_path(@boleto)
    assert_response :not_found
  end

  test "o Active Storage não tem rota pública: o arquivo só sai pelos controladores autenticados" do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_empty paths.grep(/active_storage/), "rota pública do Active Storage"
    get "/rails/active_storage/blobs/redirect/#{@boleto.boleto_pdf.blob.signed_id}/boleto.pdf"
    assert_response :not_found
  end
end
