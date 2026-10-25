require "test_helper"

# Emissão de boleto e Pix (12, R271 a R276) com o fornecedor falso: nenhum teste chama fornecedor real.
class PaymentsIssuerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @boleto_account = make_account(@alfa, modality: "boleto", environment: "production")
    @pix_account = make_account(@alfa, modality: "pix", environment: "production", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    @issuer = Payments::Issuer.new
  end

  def request(kind: "boleto", **overrides)
    @issuer.request(tenant: @alfa, kind: kind, amount_cents: 125_000, customer: @customer, due_on: Date.new(2026, 11, 30), **overrides)
  end

  def run_job(instrument) = perform_enqueued_jobs { IssueInstrumentJob.perform_now(instrument.id) }

  test "o pedido grava o instrumento emitting com os dados do pagador e enfileira o job na fila default (R271, R272)" do
    instrument = nil
    assert_enqueued_with(job: IssueInstrumentJob, queue: "default") { instrument = request(reference: [ "agreement", 77 ]) }
    assert instrument.state_emitting?
    assert_equal [ 125_000, Date.new(2026, 11, 30), "fake", @boleto_account.id ], [ instrument.amount_cents, instrument.due_on, instrument.provider, instrument.account_id ]
    assert_equal [ "Maria Souza", "52998224725" ], [ instrument.payer_name, instrument.payer_document ]
    assert_equal [ "agreement", 77 ], [ instrument.reference_type, instrument.reference_id ]
    assert_match(/\A[a-zA-Z0-9]{26,35}\z/, instrument.custom_id)
  end

  test "emite o boleto: linha digitável, PDF em disco com SHA-256 conferido, estado ativo (R271, R273)" do
    instrument = request
    run_job(instrument)
    instrument.reload
    assert instrument.state_active?
    assert_match(/\A\d{5}\.\d{5} /, instrument.digitable_line)
    assert instrument.external_id.start_with?("FAKE-BOLETO")
    assert instrument.boleto_pdf.attached?
    bytes = instrument.boleto_pdf.download
    assert_equal Digest::SHA256.hexdigest(bytes), instrument.boleto_pdf_sha256
    assert bytes.start_with?("%PDF")
    assert_equal "application/pdf", instrument.boleto_pdf.content_type
  end

  test "emite o Pix: copia e cola e a imagem do QR Code do fornecedor (R273)" do
    instrument = request(kind: "pix")
    run_job(instrument)
    instrument.reload
    assert instrument.state_active?
    assert_predicate instrument.copy_paste, :present?
    assert_equal Payments::Providers::Fake::PNG, instrument.pix_qr_png.download
    assert_equal Digest::SHA256.hexdigest(Payments::Providers::Fake::PNG), instrument.pix_qr_sha256
  end

  test "sem imagem do fornecedor, o QR Code é gerado aqui a partir do copia e cola (R273, IP-P3)" do
    Payments::Providers::Fake.omit_qr_image!
    instrument = request(kind: "pix")
    run_job(instrument)
    png = instrument.reload.pix_qr_png.download
    assert png.start_with?("\x89PNG\r\n\x1a\n".b)
    assert_not_equal Payments::Providers::Fake::PNG, png
    assert_equal Digest::SHA256.hexdigest(png), instrument.pix_qr_sha256
  end

  test "repetir o pedido com o mesmo custom_id devolve o mesmo instrumento, e dois jobs emitem uma vez (R272)" do
    first = request(custom_id: "A" * 30)
    again = nil
    assert_no_enqueued_jobs { again = request(custom_id: "A" * 30) }
    assert_equal first.id, again.id
    run_job(first)
    external = first.reload.external_id
    run_job(first)
    IssueInstrumentJob.perform_now(first.id)
    assert_equal 1, PaymentInstrument.where(custom_id: "A" * 30).count
    assert_equal external, first.reload.external_id
    assert_equal 1, Payments::Providers::Fake.store[:instruments].size
  end

  test "o custom_id é único por credor no banco e tem o formato do txid (R272)" do
    request(custom_id: "B" * 30)
    other = PaymentInstrument.new(tenant: @alfa, account: @boleto_account, provider: "fake", kind: "boleto", amount_cents: 1, due_on: Date.current, custom_id: "B" * 30)
    assert_not other.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { other.save!(validate: false) }
    assert_not PaymentInstrument.new(custom_id: "curto").valid?
  end

  test "sem documento do pagador ou com documento inválido o instrumento falha com motivo e o fornecedor não é chamado (R274)" do
    @customer.update_columns(document: "11111111111")
    invalid = request
    run_job(invalid)
    assert_equal [ "failed", "Documento do pagador inválido." ], [ invalid.reload.state, invalid.failure_reason ]
    invalid.update_columns(payer_document: nil, state: "emitting")
    run_job(invalid)
    assert_equal "Documento do pagador ausente.", invalid.reload.failure_reason
    assert_empty Payments::Providers::Fake.store[:instruments]
  end

  test "falha do fornecedor vira failed com o motivo (R271)" do
    Payments::Providers::Fake.fail_on(:issue_boleto, Payments::Providers::Error.new("valor abaixo do mínimo"))
    instrument = request
    run_job(instrument)
    assert_equal [ "failed", "valor abaixo do mínimo" ], [ instrument.reload.state, instrument.failure_reason ]
  end

  test "erro de rede: o Pix é tentado de novo; o boleto só quando a conexão nem saiu; esgotadas as tentativas, falha (R272)" do
    Payments::Providers::Fake.fail_on(:issue_pix, Payments::Providers::NetworkError.new("fora", retry_safe: false))
    Payments::Providers::Fake.fail_on(:issue_boleto, Payments::Providers::NetworkError.new("tempo esgotado", retry_safe: false))
    pix = request(kind: "pix")
    assert_raises(Payments::Providers::NetworkError) { @issuer.perform(pix) }
    assert pix.reload.state_emitting?, "o Pix é idempotente pelo txid: segue emitting para a nova tentativa"
    boleto = request
    @issuer.perform(boleto)
    assert_equal "failed", boleto.reload.state, "boleto cujo pedido pode ter sido processado não é repetido"
    assert_match(/tempo esgotado/, boleto.failure_reason)
    pix.update_columns(attempts: Payments::Issuer::MAX_ATTEMPTS - 1)
    @issuer.perform(pix)
    assert_equal "failed", pix.reload.state
  end

  test "boleto com a conexão que nem saiu é tentado de novo (R272)" do
    Payments::Providers::Fake.fail_on(:issue_boleto, Payments::Providers::NetworkError.new("inacessível", retry_safe: true), times: 1)
    boleto = request
    assert_raises(Payments::Providers::NetworkError) { @issuer.perform(boleto) }
    @issuer.perform(boleto.reload)
    assert boleto.reload.state_active?
  end

  test "se o PDF falha depois de o fornecedor emitir, a nova tentativa não emite de novo (R272)" do
    # O falso entrega o PDF na emissão; aqui o fornecedor "emitiu" antes (identificador guardado) e só a baixa do PDF falha na primeira vez.
    instrument = request
    Payments::Providers::Fake.store[:instruments]["FAKE-BOLETO-9"] = { external_id: "FAKE-BOLETO-9", status: "active", kind: "boleto", amount_cents: 125_000, pdf: Payments::Providers::Fake::PDF }
    instrument.update_columns(external_id: "FAKE-BOLETO-9", digitable_line: "34191.11111 11111.111111 11111.111111 1 00000000125000")
    Payments::Providers::Fake.fail_on(:download_boleto_pdf, Payments::Providers::NetworkError.new("fora", retry_safe: true), times: 1)
    assert_raises(Payments::Providers::NetworkError) { @issuer.perform(instrument) }
    @issuer.perform(instrument.reload)
    assert instrument.reload.state_active?
    assert_equal 1, Payments::Providers::Fake.store[:instruments].size, "nenhuma emissão nova"
  end

  test "sem conta ativa da modalidade e do ambiente não há pedido (R260)" do
    assert_raises(Payments::Issuer::NoAccount) { request(kind: "boleto", environment: "sandbox") }
    @boleto_account.update!(active: false)
    assert_raises(Payments::Issuer::NoAccount) { request }
  end

  test "o vencimento padrão vem dos dias de validade da conta" do
    @boleto_account.update!(config: @boleto_account.config.merge("expire_days" => 9))
    instrument = @issuer.request(tenant: @alfa, kind: "boleto", amount_cents: 500, customer: @customer)
    assert_equal Date.current + 9, instrument.due_on
  end

  test "cancelar o ativo chama o fornecedor; o pago nunca é cancelado nem alterado (R276)" do
    active = request
    run_job(active)
    @issuer.cancel(active)
    assert active.reload.state_canceled?
    assert_equal "canceled", Payments::Providers::Fake.store[:instruments][active.external_id][:status]
    assert_raises(Payments::Issuer::Refused) { @issuer.cancel(active) }

    paid = request
    run_job(paid)
    paid.update_columns(state: "paid")
    error = assert_raises(Payments::Issuer::Refused) { @issuer.cancel(paid) }
    assert_match(/pago não pode/, error.message)
    assert_raises(Payments::Issuer::Refused) { @issuer.change_due_date(paid, Date.current + 10) }
    assert paid.reload.state_paid?
  end

  test "mudar o vencimento: só boleto ativo, data futura, e o PDF é baixado de novo (R276)" do
    boleto = request
    run_job(boleto)
    old_sha = boleto.reload.boleto_pdf_sha256
    new_date = Date.current + 20
    @issuer.change_due_date(boleto, new_date)
    assert_equal new_date, boleto.reload.due_on
    assert_equal new_date, Payments::Providers::Fake.store[:instruments][boleto.external_id][:due_on]
    assert boleto.boleto_pdf.attached?
    assert_equal old_sha, boleto.boleto_pdf_sha256, "o PDF do falso é o mesmo; o importante é que foi baixado e conferido de novo"
    assert_raises(Payments::Issuer::Refused) { @issuer.change_due_date(boleto, Date.current) }
    pix = request(kind: "pix")
    run_job(pix)
    assert_raises(Payments::Issuer::Refused) { @issuer.change_due_date(pix, new_date) }
  end

  test "lote: um job por instrumento, espaçados pelo limite de taxa, e sem duplicar os já existentes (R272)" do
    requests = Array.new(3) { |i| { tenant: @alfa, kind: "boleto", amount_cents: 1_000 + i, customer: @customer, due_on: Date.current + 5, custom_id: "L#{i}".ljust(30, "x") } }
    instruments = nil
    assert_enqueued_jobs(3, only: IssueInstrumentJob) { instruments = @issuer.request_batch(requests, per_minute: 30) }
    times = enqueued_jobs.map { |job| job["scheduled_at"].present? ? Time.zone.parse(job["scheduled_at"].to_s) : Time.current }
    assert_in_delta 4, times.max - times.min, 1.5, "30 por minuto: um a cada 2 s, o último sai 4 s depois do primeiro"
    assert_equal 3, instruments.map(&:id).uniq.size
    assert_no_enqueued_jobs(only: IssueInstrumentJob) do
      clear_enqueued_jobs
      @issuer.request_batch(requests, per_minute: 30)
    end
  end

  test "o limite de taxa padrão é configurável" do
    assert_equal 120, Payments::Issuer.per_minute
  end

  test "o leitor entrega texto e arquivos conferidos só de instrumento entregável (R275)" do
    boleto = request
    run_job(boleto)
    reader = Payments::InstrumentReader.new(boleto.reload)
    assert_equal boleto.digitable_line, reader.text
    assert reader.pdf.start_with?("%PDF")
    assert_equal "boleto", reader.delivery.kind
    boleto.update_columns(boleto_pdf_sha256: "0" * 64)
    assert_raises(Payments::InstrumentReader::NotDeliverable) { reader.pdf }
    boleto.update_columns(state: "canceled")
    assert_raises(Payments::InstrumentReader::NotDeliverable) { Payments::InstrumentReader.new(boleto).delivery }
  end

  test "a conta que emitiu só se desativa e não se apaga (R269)" do
    assert_not @boleto_account.used?
    request
    assert @boleto_account.reload.used?
    assert_raises(Access::Refused) { Payments::AccountManager.new(users(:joana)).destroy(@boleto_account) }
  end

  test "ao anonimizar o cliente, o pagador do instrumento perde nome, documento e endereço" do
    instrument = request
    instrument.update_columns(payer_address: { "street" => "Rua A" })
    Titular::Anonymizer.in_batch(@alfa.id, [ @customer.id ])
    instrument.reload
    assert_not_equal "Maria Souza", instrument.payer_name
    assert_not_equal "52998224725", instrument.payer_document
    assert_equal({}, instrument.payer_address)
  end
end
