require "net/http"

module Payments
  module Providers
    # Cliente HTTP dos adaptadores (12). Fica fora deles para ser trocado nos testes: nenhum teste chama fornecedor real. Faz TLS com certificado de
    # cliente (mTLS) a partir de objetos em memória (`tls: { cert:, key: }`), nunca de arquivo. Falha de conexão vira `NetworkError`, dizendo se
    # repetir é seguro: a que acontece antes de o pedido sair (conexão, handshake) é; a que acontece depois (leitura) pode ter sido processada.
    class HttpClient
      Response = Data.define(:status, :body, :headers)

      class TooLarge < Error; end

      def request(method, url, headers: {}, body: nil, tls: nil, open_timeout: 5, read_timeout: 30, max_bytes: 5.megabytes)
        uri = URI.parse(url)
        raise Error, "endereço do fornecedor inválido" unless uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        if tls
          http.cert = tls.fetch(:cert)
          http.key = tls.fetch(:key)
        end
        request = Net::HTTPGenericRequest.new(method.to_s.upcase, !body.nil?, true, uri.request_uri, headers)
        request.body = body if body
        perform(http, request, max_bytes)
      rescue Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, OpenSSL::SSL::SSLError
        raise NetworkError.new("fornecedor inacessível", retry_safe: true)
      rescue Net::ReadTimeout, EOFError, Errno::ECONNRESET, Errno::EPIPE
        raise NetworkError.new("o fornecedor não respondeu a tempo", retry_safe: false)
      end

      private
        def perform(http, request, max_bytes)
          http.start do |connection|
            connection.request(request) do |response|
              chunks = +""
              response.read_body do |chunk|
                chunks << chunk
                raise TooLarge, "resposta maior que o limite" if chunks.bytesize > max_bytes
              end
              return Response.new(status: response.code.to_i, body: chunks, headers: response.each_header.to_h)
            end
          end
        end
    end
  end
end
