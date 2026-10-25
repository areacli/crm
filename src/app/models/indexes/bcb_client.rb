require "net/http"

module Indexes
  # Cliente da API pública SGS do Banco Central (decisão 0009): a única chamada de saída do sistema, e não envia dado nenhum do CRM.
  # Devolve a série como pares [mês, valor em texto]; a validação e a gravação são de `Indexes::Fetch`.
  class BcbClient
    TIMEOUT = 20

    def initialize(http: Net::HTTP) = @http = http

    # `from` e `to` são datas; o Banco Central responde `[{"data":"01/09/2026","valor":"0.42"}]`.
    def series(code, from:, to:)
      uri = URI("https://api.bcb.gov.br/dados/serie/bcdata.sgs.#{Integer(code)}/dados")
      uri.query = URI.encode_www_form(formato: "json", dataInicial: from.strftime("%d/%m/%Y"), dataFinal: to.strftime("%d/%m/%Y"))
      response = @http.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri, "Accept" => "application/json") }
      raise SourceError, I18n.t("indexes.errors.http", status: response.code) unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError
      raise SourceError, I18n.t("indexes.errors.unreachable")
    rescue JSON::ParserError
      raise SourceError, I18n.t("indexes.errors.invalid")
    end
  end
end
