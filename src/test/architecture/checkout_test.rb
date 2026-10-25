require "test_helper"

# Checkout de cartão e links (12, parte C): o dado de cartão nunca toca o servidor, a página pública não tem terceiros, a política de segurança de
# conteúdo só libera o que o adaptador declara, e nada de fornecedor específico fica fora do adaptador (R278, R279).
class CheckoutArchitectureTest < ActiveSupport::TestCase
  ROOT = Rails.root

  def sources(glob) = Dir[ROOT.join(glob)].reject { |file| File.directory?(file) }

  test "nenhum campo de cartão tem atributo name: só payment_token e installments são enviados" do
    named = sources("app/views/checkouts/**/*.erb").flat_map { |file| File.read(file).scan(/<(?:input|select|textarea)\b[^>]*>/m) }.select { |tag| tag.match?(/\sname\s*=|name:/) }
    assert_equal 2, named.size, named.inspect
    assert named.all? { |tag| tag.match?(/name="(payment_token|installments)"/) }, named.inspect
    card_fields = sources("app/views/checkouts/**/*.erb").flat_map { |file| File.read(file).scan(/<input\b[^>]*id="cartao-[^>]*>/m) }
    assert_equal 4, card_fields.size
    assert card_fields.none? { |tag| tag.match?(/\sname\s*=/) }, "campo de cartão com name"
  end

  test "o JavaScript da página não envia nada por conta própria, não guarda e não registra: o cartão só vai à biblioteca do fornecedor" do
    forbidden = /fetch\(|XMLHttpRequest|sendBeacon|WebSocket\(|localStorage|sessionStorage|document\.cookie|console\.\w+|\.setAttribute\(\s*["']name|\.name\s*=|FormData/
    (sources("app/javascript/checkout.js") + sources("app/javascript/payments/**/*.js")).each do |file|
      assert_no_match forbidden, File.read(file).gsub(%r{//.*$}, ""), "#{file.delete_prefix("#{ROOT}/")} faz algo que o checkout não pode"
    end
  end

  test "o servidor só lê payment_token e installments no POST do cartão, e o formulário não aceita outro dado" do
    source = File.read(ROOT.join("app/controllers/checkouts/card_payments_controller.rb"))
    assert_includes source, "params.expect(:payment_token, :installments)"
    assert_empty source.scan(/params(?:\.expect\((?!:payment_token, :installments\))|\[(?!:token\]))/), "o POST do cartão só lê o token do link, payment_token e installments"
    assert_no_match(/params\[:(number|cvv|card|holder|expir)/, source)
    models = sources("app/{controllers,models,jobs,views}/**/*").reject { |f| f.include?("providers/fake") }
    offenders = models.select { |file| File.read(file).match?(/\b(card_number|cvv|cvc|security_code|card_holder|expiration_month|expiration_year|cardNumber)\b/i) }
    assert_empty offenders.map { |f| f.delete_prefix("#{ROOT}/") }
  end

  test "nenhuma coluna guarda número, validade, código ou titular do cartão, nem o payment_token" do
    names = %w[payment_checkouts payment_instruments].flat_map { |table| ActiveRecord::Base.connection.columns(table).map(&:name) }
    assert_empty names.grep(/card_number|cvv|cvc|holder|expir.*(month|year)|pan\z|payment_token|\Atoken_/i)
    assert_equal [ "token" ], ActiveRecord::Base.connection.columns("payment_checkouts").map(&:name).grep(/token/), "só o token do link (o endereço), não o do cartão"
  end

  test "o filtro de parâmetros do log cobre os nomes de dado de cartão e o payment_token" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { "payment_token" => "t", "number" => "4111", "card_number" => "4111", "cvv" => "1", "cvc" => "1", "card" => "x", "holder_name" => "x", "holderName" => "x",
               "expirationMonth" => "1", "expiration_year" => "1", "token" => "x", "pan" => "x", "installments" => "3" }
    filtered = filter.filter(params)
    assert_equal [ "installments" ], filtered.reject { |_k, v| v == "[FILTERED]" }.keys
  end

  test "a política de segurança de conteúdo vem do manifesto: sem curinga, sem http, só origens https e nenhuma diretiva insegura" do
    Payments::Providers.names.each do |name|
      manifest = Payments::Providers.manifest(name)
      next unless manifest.supports?("card")

      account = PaymentAccount.new(provider: name, modality: "card", environment: "production")
      hosts = Payments::Providers.adapter(name).card_checkout_hosts(account)
      assert_equal %i[connect frame img script], hosts.keys.sort
      hosts.values.flatten.each { |origin| assert_match(%r{\Ahttps://[a-z0-9.-]+\z}, origin, "#{name}: #{origin}") }
    end
    source = File.read(ROOT.join("app/controllers/checkout_base_controller.rb"))
    assert_no_match(/unsafe|["']\*|\*\.|https?:\/\//, source.gsub(/#.*$/, ""), "nenhum domínio nem diretiva insegura escrita no controlador")
  end

  test "o módulo e a biblioteca de cada adaptador de cartão existem no importmap, na árvore e com SHA-256 conferido" do
    importmap = File.read(ROOT.join("config/importmap.rb"))
    Payments::Providers.names.each do |name|
      manifest = Payments::Providers.manifest(name)
      next unless manifest.supports?("card")

      declared = manifest.capabilities.fetch(:card_checkout)
      assert_includes importmap, %(pin "#{declared.fetch(:driver)}"), "módulo do adaptador #{name} fora do importmap"
      assert File.exist?(ROOT.join("app/javascript", "#{declared.fetch(:driver)}.js")), "módulo #{declared.fetch(:driver)} ausente"
      next unless declared[:script]

      assert_includes importmap, %(pin "#{declared[:script]}")
      file = ROOT.join("vendor/javascript/#{declared[:script]}.js")
      assert File.exist?(file), "biblioteca #{declared[:script]} ausente da árvore"
      assert_equal declared.fetch(:script_sha256), Digest::SHA256.hexdigest(File.binread(file)), "a biblioteca mudou sem mudar o SHA-256 do manifesto"
      assert declared[:script_version].present?
    end
  end

  test "nada de CDN: o importmap e os módulos não apontam para endereço externo" do
    assert_no_match(%r{https?://}, File.read(ROOT.join("config/importmap.rb")).gsub(/#.*$/, ""))
    (sources("app/javascript/**/*.js") + sources("app/views/{checkouts,layouts}/**/*.erb")).each do |file|
      assert_no_match(%r{https?://}, File.read(file).gsub(%r{//.*$}, ""), "#{file.delete_prefix("#{ROOT}/")} aponta para endereço externo")
    end
  end

  test "nada específico da Efí fora do adaptador: o resto conhece só o contrato" do
    allowed = %r{app/models/payments/providers/efi|app/javascript/payments/drivers/efi\.js|vendor/|config/importmap\.rb|config/initializers/payment_providers\.rb|config/locales/|config/credentials}
    pattern = /efi\b|efipay|sejaefi|gerencianet|clearsale|fpcs-monitor|payee_code/i
    offenders = sources("{app,config,lib}/**/*").reject { |file| file.delete_prefix("#{ROOT}/").match?(allowed) || file.match?(/\.(enc|key|png|svg|woff2|ico)\z/) }
                                                .select { |file| File.read(file).match?(pattern) }
    assert_empty offenders.map { |file| file.delete_prefix("#{ROOT}/") }
  end

  test "a página pública não herda do back office: sem sessão, sem login, com limite de requisições, e os controladores são só do namespace" do
    assert_not_includes CheckoutBaseController.ancestors, Authentication
    assert_not_includes CheckoutBaseController.ancestors, ApplicationController
    assert_includes File.read(ROOT.join("app/controllers/checkout_base_controller.rb")), "rate_limit"
    assert_includes File.read(ROOT.join("app/controllers/checkouts/card_payments_controller.rb")), "rate_limit"
    sources("app/controllers/checkouts/*.rb").each do |file|
      assert_match(/< CheckoutBaseController/, File.read(file), file)
    end
    public_routes = Rails.application.routes.routes.select { |route| route.path.spec.to_s.start_with?("/pagar") }
    assert_equal [ %w[GET boletos#show], %w[GET checkouts#show], %w[GET installments#index], %w[GET qr_codes#show], %w[GET situations#show], %w[POST card_payments#create] ],
                 public_routes.map { |route| [ route.verb, route.defaults[:controller].to_s.delete_prefix("checkouts/").then { |c| "#{c}##{route.defaults[:action]}" } ] }.sort
    assert public_routes.all? { |route| route.path.spec.to_s.start_with?("/pagar/:token") }
  end

  test "o back office não cria link nem cobra cartão: o serviço só é chamado pela página pública" do
    offenders = sources("app/controllers/**/*.rb").reject { |file| file.include?("app/controllers/checkouts") || file.include?("checkout_base") }
                                                  .select { |file| File.read(file).match?(/Payments::Checkouts\.(create|renew|cancel)|CardCharger|PaymentCheckout\.(create|new)/) }
    assert_empty offenders
    staff_routes = Rails.application.routes.routes.reject { |route| route.path.spec.to_s.start_with?("/pagar") }.map { |route| [ route.defaults[:controller], route.defaults[:action] ].join("#") }
    assert_empty staff_routes.grep(/checkout/), "rota de checkout no back office"
  end

  test "o layout público não tem menu, usuário nem script embutido e mantém robots noindex e referrer fechado" do
    layout = File.read(ROOT.join("app/views/layouts/pagamento.html.erb"))
    assert_no_match(/Current\.user|authenticated\?|navegacao|<script(?![^>]*src=)/, layout)
    assert_includes layout, 'name="robots" content="noindex, nofollow, noarchive"'
    assert_includes layout, 'name="referrer" content="no-referrer"'
  end
end
