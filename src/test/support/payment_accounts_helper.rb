# Contas de pagamento nos testes (12): certificados .p12 gerados na hora e contas prontas do fornecedor falso.
module PaymentAccountsHelper
  SENTINEL_PREFIX = "SEGREDO-DE-TESTE-".freeze

  def rsa_key = (PaymentAccountsHelper.key ||= OpenSSL::PKey::RSA.new(2048))

  def self.key = @key
  def self.key=(value)
    @key = value
  end

  # Conteúdo de um .p12 com o titular informado. `days`: validade a partir de agora (negativo = já vencido); `with_key: false` gera arquivo só com certificado.
  def make_p12(subject: "CN=Escola Alfa", days: 365, password: "", with_key: true)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = SecureRandom.random_number(1 << 32)
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse(subject)
    certificate.not_before = Time.current - [ days.abs + 10, 400 ].max.days
    certificate.not_after = Time.current + days.days
    certificate.public_key = rsa_key.public_key
    certificate.sign(rsa_key, OpenSSL::Digest.new("SHA256"))
    return OpenSSL::PKCS12.create(password, "teste", rsa_key, certificate).to_der if with_key

    # O Ruby não cria .p12 sem chave; a linha de comando do OpenSSL cria.
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cert.pem"), certificate.to_pem)
      system("openssl", "pkcs12", "-export", "-nokeys", "-in", File.join(dir, "cert.pem"), "-out", File.join(dir, "out.p12"), "-passout", "pass:#{password}", exception: true)
      File.binread(File.join(dir, "out.p12"))
    end
  end

  # Arquivo enviado (Rack::Test::UploadedFile) com o conteúdo informado.
  def p12_upload(**options)
    file = Tempfile.new([ "certificado", ".p12" ], binmode: true)
    file.write(make_p12(**options))
    file.flush
    (@upload_files ||= []) << file
    Rack::Test::UploadedFile.new(file.path, "application/x-pkcs12", true)
  end

  def sentinel(name = SecureRandom.hex(6)) = "#{SENTINEL_PREFIX}#{name}"

  # Conta do fornecedor falso, ativa, ligada a um canal do credor.
  def make_account(tenant, modality: "boleto", environment: "sandbox", nickname: nil, secrets: { "api_key" => "chave-1" }, config: { "connection_result" => "ok" }, active: true, provider: "fake")
    channel = tenant.payment_channels.first || make_channel(tenant)
    account = tenant.payment_accounts.build(channel: channel, modality: modality, provider: provider, environment: environment, nickname: nickname || "Conta #{modality} #{environment} #{SecureRandom.hex(2)}", active: active)
    account.assign_values(config: config, secrets: secrets)
    account.save!
    account
  end
end
