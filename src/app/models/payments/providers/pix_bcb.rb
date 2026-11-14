module Payments
  module Providers
    # O que é do padrão da API Pix do Banco Central (12, revisão 4) e serve a todo adaptador de Pix que o segue (a Efí e o Bradesco): o corpo da
    # cobrança com vencimento (`cobv`), a leitura dela no nosso vocabulário, a leitura de um Pix recebido em avisos (o mesmo para o webhook e para a
    # lista `GET /pix`, R284b: o `endToEndId` é o identificador nos dois caminhos) e a mensagem curta de erro no formato da RFC 7807. Sem rede.
    # Valores em texto com duas casas ("1250.00"); datas ISO 8601.
    module PixBcb
      module_function

      STATUS = { "ATIVA" => "active", "CONCLUIDA" => "paid", "REMOVIDA_PELO_USUARIO_RECEBEDOR" => "canceled", "REMOVIDA_PELO_PSP" => "canceled" }.freeze
      # Juros: "percentual ao mês (dias corridos)" na tabela do Banco Central; multa e desconto até a data: "percentual" (2).
      INTEREST_MODALITY = 3
      FINE_MODALITY = 2
      DISCOUNT_MODALITY = 2
      CANCELED = "REMOVIDA_PELO_USUARIO_RECEBEDOR".freeze

      def person(document) = document.to_s.length == 14 ? :cnpj : :cpf

      def decimal(cents) = format("%d.%02d", *cents.to_i.divmod(100))

      def percent(value) = format("%.2f", value.to_d)

      # Corpo da `cobv`. `discount_until`: a data do desconto (a Efí aceita o próprio vencimento; o Bradesco pede data menor que o vencimento).
      def cobv_body(amount_cents:, due_on:, payer:, pix_key:, options:, discount_until: due_on)
        debtor = { "nome" => payer[:name].to_s, person(payer[:document]).to_s => payer[:document] }
        address = (payer[:address] || {}).transform_keys(&:to_s)
        debtor.merge!("logradouro" => [ address["street"], address["number"] ].compact_blank.join(", ").presence, "cidade" => address["city"].presence,
                      "uf" => address["state"].presence, "cep" => address["zip"].presence).compact! if address.values_at("street", "city", "state", "zip").all?(&:present?)
        value = { "original" => decimal(amount_cents) }
        value["multa"] = { "modalidade" => FINE_MODALITY, "valorPerc" => percent(options[:fine_percent]) } if options[:fine_percent].to_d.positive?
        value["juros"] = { "modalidade" => INTEREST_MODALITY, "valorPerc" => percent(options[:interest_percent]) } if options[:interest_percent].to_d.positive?
        if options[:discount_percent].to_d.positive?
          value["desconto"] = { "modalidade" => DISCOUNT_MODALITY, "descontoDataFixa" => [ { "data" => discount_until.iso8601, "valorPerc" => percent(options[:discount_percent]) } ] }
        end
        body = { "calendario" => { "dataDeVencimento" => due_on.iso8601, "validadeAposVencimento" => options.fetch(:after_due_days, 30).to_i }, "devedor" => debtor,
                 "valor" => value, "chave" => pix_key }
        body["solicitacaoPagador"] = options[:message].to_s.first(140) if options[:message].present?
        body
      end

      # A `cobv` no nosso vocabulário. Status desconhecido é erro (nada se decide sobre um estado que não se entende).
      def issued(data, txid, unknown_status_message:)
        status = STATUS[data["status"].to_s] or raise Error, unknown_status_message
        amount = BigDecimal(data.dig("valor", "original").to_s.presence || "0") * 100
        payments = Array(data["pix"])
        paid = payments.sum { |pix| cents_of(pix["valor"]) }
        refunded = payments.sum { |pix| Array(pix["devolucoes"]).select { |refund| refund["status"].to_s == "DEVOLVIDO" }.sum { |refund| cents_of(refund["valor"]) } }
        Issued.new(external_id: (data["txid"] || txid).to_s, status: status, amount_cents: amount.to_i.nonzero?,
                   due_on: (Date.iso8601(data.dig("calendario", "dataDeVencimento").to_s) rescue nil), copy_paste: data["pixCopiaECola"].presence,
                   paid_cents: (paid.positive? ? paid : nil), refunded_cents: (refunded if payments.any?))
      end

      # Um Pix recebido (`endToEndId` é a chave) e as devoluções dele (uma por `id` e estado, porque o mesmo `id` passa de EM_PROCESSAMENTO a DEVOLVIDO).
      # Serve ao webhook e à lista: o mesmo pagamento dá o mesmo `event_id` pelos dois caminhos (R284b). Pix sem `txid` não é de cobrança nossa.
      # Lê `horario` e a grafia com acento que um manual traz; ignora o que não conhece (campos do pagador incluídos).
      def received_notifications(pix)
        return [] unless pix.is_a?(Hash) && pix["endToEndId"].present?

        e2e = pix["endToEndId"].to_s
        txid = pix["txid"].presence
        received = Notification.new(event_id: e2e, kind: :paid, external_id: txid, amount_cents: cents_of(pix["valor"]).nonzero?, occurred_at: time_of(pix["horario"] || pix["horário"]),
                                    end_to_end_id: e2e)
        refunds = Array(pix["devolucoes"]).filter_map do |refund|
          next unless refund.is_a?(Hash) && refund["id"].present?

          times = refund["horario"] || refund["horário"] || {}
          Notification.new(event_id: "#{e2e}:#{refund['id']}:#{refund['status']}", kind: (refund["status"].to_s == "DEVOLVIDO" ? :refunded : :other), external_id: txid,
                           amount_cents: cents_of(refund["valor"]).nonzero?, occurred_at: time_of(times.is_a?(Hash) ? (times["liquidacao"] || times["solicitacao"]) : nil),
                           end_to_end_id: e2e, current_status: refund["status"].to_s.first(40))
        end
        [ received, *refunds ]
      end

      # Parâmetros de uma página da lista de Pix recebidos (`GET /pix`), só os que têm `txid` (os nossos).
      def received_list_query(from:, to:, page:, per_page: 100)
        { "inicio" => from.utc.iso8601, "fim" => to.utc.iso8601, "txIdPresente" => "true", "paginacao.paginaAtual" => page, "paginacao.itensPorPagina" => per_page }.to_query
      end

      # Há outra página depois desta?
      def more_pages?(data, page)
        total = data.dig("parametros", "paginacao", "quantidadeDePaginas").to_i
        page + 1 < total
      end

      # "110.00" (reais, em texto) em centavos; nada válido = 0.
      def cents_of(value)
        (BigDecimal(value.to_s) * 100).round.to_i
      rescue ArgumentError, TypeError
        0
      end

      def time_of(value)
        Time.zone.parse(value.to_s).presence if value.present?
      rescue ArgumentError
        nil
      end

      # Mensagem curta e segura de uma resposta de erro: nunca o corpo inteiro, nunca o que foi enviado.
      def error_message(json)
        return "resposta de erro do fornecedor" unless json.is_a?(Hash)

        description = json["error_description"]
        text = case description
        when Hash then description["message"] || description["property"]
        when String then description
        end
        text ||= [ json["title"], json["detail"] ].compact.join(": ").presence
        violations = Array(json["violacoes"]).filter_map { |item| [ item["propriedade"], item["razao"] ].compact.join(" ") if item.is_a?(Hash) }
        text = [ text, *violations ].compact.join("; ").presence || json["error"] || json["mensagem"]
        text.to_s.gsub(/[[:cntrl:]]/, " ").squish.first(200).presence || "resposta de erro do fornecedor"
      end
    end
  end
end
