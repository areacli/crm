require "test_helper"

# Instrumentos de pagamento (12, parte B): nada de link do fornecedor, nada de dado de cartão, nada de emissão pela interface (R270, R273, R278, R279).
class InstrumentsArchitectureTest < ActiveSupport::TestCase
  test "nenhuma coluna de instrumento guarda endereço do fornecedor nem dado de cartão" do
    columns = PaymentInstrument.column_names
    assert_empty columns.grep(/\A(link|url|billet_link|pdf_url|location|loc_|card|pan|cvv|number|holder|expir)/i), "coluna suspeita: #{columns.grep(/link|url|card|cvv|pan/i)}"
    assert_empty columns.grep(/token|secret|password|key/i), "o instrumento não guarda segredo nem token"
  end

  test "o resumo da resposta e o motivo de falha nunca levam endereço do fornecedor" do
    efi = Payments::Providers::Efi::Payloads
    message = efi.error_message({ "error_description" => "falhou" })
    assert_not_includes message, "http"
    source = File.read(Rails.root.join("app/models/payments/issuer.rb"))
    assert_no_match(/\.link|billet_link|\[.link.\]/, source)
  end

  test "nenhum código da aplicação redireciona a endereço externo de fornecedor" do
    sources = Dir[Rails.root.join("app/controllers/**/*.rb")].map { |file| [ file, File.read(file) ] }
    offenders = sources.select { |_file, text| text.match?(/redirect_to\s+["'(]*https?:|redirect_to\s+.*\b(billet_link|pdf_url|location)\b/i) }
    assert_empty offenders.map(&:first)
  end

  test "dado de cartão não é tratado: nenhum atributo, parâmetro ou coluna chama número, cvv ou validade de cartão" do
    sources = Dir[Rails.root.join("app/{controllers,models,jobs}/**/*.rb")].reject { |f| f.include?("providers/fake") }
    offenders = sources.select { |file| File.read(file).match?(/\b(card_number|cvv|cvc|security_code|card_holder|expiration_month|expiration_year)\b/i) }
    assert_empty offenders
  end

  test "as rotas de instrumento são só de leitura (GET) e nenhuma serve a quem está sem sessão" do
    routes = Rails.application.routes.routes.select { |route| route.defaults[:controller].to_s.start_with?("payment_instruments") }
    assert_equal 3, routes.size
    assert_equal [ "GET" ], routes.map(&:verb).uniq
    assert_operator PaymentInstrumentsController, :<, ApplicationController
    assert_includes ApplicationController.ancestors, Authentication
  end

  test "o serviço de emissão não é chamado por nenhum controlador" do
    offenders = Dir[Rails.root.join("app/controllers/**/*.rb")].select { |file| File.read(file).match?(/Payments::Issuer|IssueInstrumentJob/) }
    assert_empty offenders
  end

  test "o Active Storage guarda em disco, sem rotas públicas, sem análise e com filas do Sidekiq" do
    assert_equal false, Rails.configuration.active_storage.draw_routes
    assert_equal [], Rails.configuration.active_storage.analyzers
    assert_equal :default, Rails.configuration.active_storage.queues.purge
    assert_equal :default, Rails.configuration.active_storage.queues.analysis
    service = ActiveStorage::Blob.service
    assert_kind_of ActiveStorage::Service::DiskService, service
  end

  test "o Pix gera o QR Code local em PNG a partir do texto" do
    png = Payments::QrCode.png("00020126580014br.gov.bcb.pix0136123e4567-e89b-12d3-a456-4266141740005204000053039865802BR5913Fulano6009SAO PAULO62070503***6304ABCD")
    assert png.start_with?("\x89PNG\r\n\x1a\n".b)
    assert_operator png.bytesize, :>, 500
    assert_raises(ArgumentError) { Payments::QrCode.png("") }
  end
end
