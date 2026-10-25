module Payments
  # Certificado .p12 de uma conta de pagamento (12, R263). Abre o arquivo só em memória, recusa o que não presta e devolve apenas titular,
  # validade e impressão digital SHA-256: nada do conteúdo nem da senha sai daqui.
  class Certificate
    MAX_BYTES = 64.kilobytes

    # `reason`: unreadable, too_large, no_private_key ou expired (a mensagem vem do arquivo de idioma).
    class Invalid < StandardError
      attr_reader :reason

      def initialize(reason, **details)
        @reason = reason
        super(I18n.t("payments.certificate.#{reason}", **details))
      end
    end

    Info = Data.define(:subject, :not_after, :sha256) do
      def to_h = { "subject" => subject, "not_after" => not_after.iso8601, "sha256" => sha256 }
    end

    def self.read(bytes, password, now: Time.current)
      raise Invalid.new(:too_large) if bytes.bytesize > MAX_BYTES

      pkcs12 = begin
        OpenSSL::PKCS12.new(bytes, password.to_s)
      rescue OpenSSL::PKCS12::PKCS12Error, ArgumentError
        raise Invalid.new(:unreadable)
      end
      raise Invalid.new(:no_private_key) unless pkcs12.key && pkcs12.certificate

      certificate = pkcs12.certificate
      expires_on = certificate.not_after.in_time_zone.to_date
      raise Invalid.new(:expired, date: expires_on.strftime("%d/%m/%Y")) if certificate.not_after <= now

      Info.new(subject: subject_of(certificate).first(200), not_after: expires_on,
               sha256: OpenSSL::Digest::SHA256.hexdigest(certificate.to_der).scan(/../).join(":").upcase)
    end

    # "CN=Escola Alfa, O=..." em UTF-8 (o formato RFC 2253 do OpenSSL escapa os acentos).
    def self.subject_of(certificate)
      certificate.subject.to_a.map { |name, value, _type| "#{name}=#{value.dup.force_encoding(Encoding::UTF_8)}" }.join(", ")
    end
  end
end
