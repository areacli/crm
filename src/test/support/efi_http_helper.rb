# Cliente HTTP falso da Efí para os testes (12): respostas gravadas à mão, nenhuma chamada real. Cada resposta é uma regra (método, trecho do
# endereço) com o status e o corpo; o falso guarda os pedidos feitos para os testes conferirem corpo, cabeçalhos e o certificado.
module EfiHttpHelper
  Request = Data.define(:method, :url, :headers, :body, :tls)

  # Cliente que recusa qualquer chamada: é o padrão em todos os testes (nenhum teste chama a Efí real).
  class Blocked
    def request(method, url, **)
      raise "teste tentou chamar o fornecedor real: #{method.to_s.upcase} #{url}"
    end
  end

  class FakeClient
    attr_reader :requests

    def initialize = (@rules = []; @requests = [])

    # `respond` pode ser um Hash { status:, body:, raw: } ou um bloco que recebe o Request e devolve esse Hash (ou levanta o erro de rede).
    def on(method, fragment, status: 200, body: {}, raw: nil, &block)
      @rules << { method: method.to_s, fragment: fragment, response: block || { status: status, body: body, raw: raw } }
      self
    end

    def request(method, url, headers: {}, body: nil, tls: nil, **_options)
      call = Request.new(method: method.to_s, url: url, headers: headers, body: body, tls: tls)
      @requests << call
      rule = @rules.reverse.find { |r| r[:method] == method.to_s && url.include?(r[:fragment]) } or raise "sem resposta gravada para #{method.to_s.upcase} #{url}"
      response = rule[:response].respond_to?(:call) ? rule[:response].call(call) : rule[:response]
      Payments::Providers::HttpClient::Response.new(status: response[:status], body: response[:raw] || response[:body].to_json, headers: {})
    end

    def to(fragment) = requests.select { |r| r.url.include?(fragment) }
  end

  def use_efi_client(client)
    Payments::Providers::Efi.http_client = client
    client
  end

  # Falso já com a autenticação das duas APIs respondida.
  def efi_client
    FakeClient.new.on(:post, "/v1/authorize", body: { "access_token" => "TOKEN-COBRANCAS", "expires_in" => 600 })
                  .on(:post, "/oauth/token", body: { "access_token" => "TOKEN-PIX", "expires_in" => 3600 })
  end

  # Conta Efí pronta (credenciais de teste; para Pix, com .p12).
  def make_efi_account(tenant, modality: "boleto", environment: "sandbox", nickname: nil)
    channel = tenant.payment_channels.first || make_channel(tenant)
    account = tenant.payment_accounts.build(channel: channel, modality: modality, provider: "efi", environment: environment, nickname: nickname || "Efí #{modality} #{SecureRandom.hex(2)}")
    secrets = { "client_id" => "Client_Id_#{SecureRandom.hex(4)}", "client_secret" => "Client_Secret_#{SecureRandom.hex(4)}" }
    config = { "pix_key" => "pix@alfa.com.br", "fine_percent" => 2, "interest_percent" => 1, "write_off_days" => 30 }
    config = config.merge("payee_code" => "ac0123456789abcdef", "max_installments" => 6) if modality == "card"
    files = {}
    if modality == "pix"
      file = Tempfile.new([ "cert", ".p12" ], binmode: true)
      file.write(make_p12)
      file.flush
      (@efi_files ||= []) << file
      files["certificate"] = Rack::Test::UploadedFile.new(file.path, "application/x-pkcs12", true)
    end
    account.assign_values(config: config, secrets: secrets, files: files)
    account.save!
    account
  end
end
