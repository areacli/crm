module Payments
  module Providers
    class Bradesco
      # Corpos e leituras da API de cobrança do Bradesco (manual 1.6.4), sem rede, e o que o Pix do Bradesco tem de diferente do padrão. "(C l. N)" é a
      # linha do texto extraído do manual de cobrança 1.6.4. O manual muda de formato de uma API para outra: datas `DD.MM.AAAA` no
      # registro, `DDMMAAAA` na consulta, na alteração e na lista de liquidados, ISO no aviso; valor decimal na ida do registro e em centavos na volta e
      # nas listas, decimal em texto no aviso (leitura, seção 10). Onde a tabela e o exemplo divergem, vale o exemplo, e o roteiro de homologação confere.
      module Payloads
        module_function

        # Espécies que servem à cobrança (C l. 1705-1773; BR9): a sigla é o que a integração guarda, o número é o que o registro manda.
        SPECIES = { "DM" => 2, "DS" => 4, "RC" => 17, "FAT" => 18, "ME" => 21, "DD" => 23, "OUT" => 99 }.freeze
        # Situação do título (Tabela 1, C l. 3443-3567) no nosso vocabulário. Pago: 13, 61, 62; vencido por decurso: 53; baixas: a faixa 51 a 73 e o 98.
        # 56 e 66 a 69 ("cobrado", "crédito EXDD") ficam como ativos até a homologação dizer se são pagamento (o pagamento nunca é inventado, R283).
        PAID = [ 13, 61, 62 ].freeze
        EXPIRED = [ 53 ].freeze
        CANCELED = [ 51, 52, 54, 55, 57, 58, 59, 60, 63, 64, 65, 70, 71, 72, 73, 98 ].freeze
        WRITE_OFF_CODE = 57
        # Códigos de indisponibilidade: do registro (-99, 2, 10; C l. 1502-1522) e das outras APIs (C l. 2322, 4260, 4819, 4864).
        REGISTRATION_UNAVAILABLE = [ -99, 2, 10 ].freeze
        REGISTRATION_TAKEN = 69
        UNAVAILABLE_CAUSES = %w[CBTT9100 CBTT9002 CBTT9000 CBTT1014 CBCA0080].freeze
        NOT_FOUND_CAUSE = "CBTT0552".freeze

        # ---- Texto e números ----

        # Só letras sem acento, números e espaço (C l. 206-208), em maiúsculas, cortado no que o banco guarda (R284i, BR8).
        def text(value, max)
          I18n.transliterate(value.to_s).upcase.gsub(/[^A-Z0-9 ]/, " ").squish.first(max)
        end

        # O nosso identificador (seu número, controle do participante): letras e números, sem mudar maiúsculas e minúsculas (o `custom_id` as distingue).
        def identifier(value, max) = value.to_s.gsub(/[^A-Za-z0-9]/, "").last(max)

        def digits(value) = value.to_s.gsub(/\D/, "")

        # CNPJ (14) em raiz de 8, filial de 4 e controle de 2; CPF (11) em raiz de 9, filial 0 e controle de 2 (C l. 276-286).
        def document_parts(document)
          number = digits(document)
          case number.length
          when 14 then { root: number[0, 8].to_i, branch: number[8, 4].to_i, control: number[12, 2].to_i }
          when 11 then { root: number[0, 9].to_i, branch: 0, control: number[9, 2].to_i }
          else raise Error, I18n.t("payments.providers.bradesco.errors.beneficiary_document")
          end
        end

        def agency(account) = digits(account.config["agency"]).rjust(4, "0").last(4)

        def account_number(account) = digits(account.config["account_number"]).rjust(7, "0").last(7)

        def wallet(account) = account.config["wallet"].to_i

        # Negociação: 11 posições (agência e conta) nas APIs; 18 no registro, com sete zeros no meio (C l. 290-298, 2180-2182).
        def negotiation(account) = "#{agency(account)}#{account_number(account)}".to_i

        def negotiation18(account) = "#{agency(account)}0000000#{account_number(account)}".to_i

        def our_number(value) = digits(value).rjust(11, "0").last(11)

        def contract(account)
          parts = document_parts(account.config["beneficiary_document"])
          { "cpfCnpj" => { "cpfCnpj" => parts[:root], "filial" => parts[:branch], "controle" => parts[:control] }, "produto" => wallet(account), "negociacao" => negotiation(account) }
        end

        # 125599 -> 1255.99 (número JSON com duas casas, como no exemplo do registro, C l. 1127).
        def reais(cents) = (cents.to_i / 100.0).round(2)

        # Centavos de um valor que pode vir em centavos (inteiro) ou em reais com ponto (texto ou decimal).
        def cents(value)
          case value
          when Integer then value
          when Float then (value * 100).round
          when String then value.include?(".") ? (BigDecimal(value.strip) * 100).round.to_i : value.to_i
          else 0
          end
        rescue ArgumentError
          0
        end

        # "21.09.2025", "21/09/2025", "21092025", "2025-09-21" ou 21092025; zero ou vazio = nil.
        def date(value)
          text = value.to_s.strip
          return if text.empty? || text.delete("0").empty?

          case text
          when /\A\d{4}-\d{2}-\d{2}\z/ then Date.iso8601(text)
          when %r{\A(\d{2})[./](\d{2})[./](\d{4})\z} then Date.new($3.to_i, $2.to_i, $1.to_i)
          when /\A\d{7,8}\z/ then (padded = text.rjust(8, "0")) && Date.new(padded[4, 4].to_i, padded[2, 2].to_i, padded[0, 2].to_i)
          end
        rescue Date::Error
          nil
        end

        def dotted(date) = date.strftime("%d.%m.%Y")

        def compact_date(date) = date.strftime("%d%m%Y").to_i

        # ---- Registro (C l. 262-1182) ----

        # Todos os campos do layout vão, os não usados com 0 ou vazio (C l. 199-205). Pagador sem endereço completo não se registra: o banco exige
        # logradouro, número, bairro, município e UF.
        def registration_body(account, our_number:, custom_id:, amount_cents:, due_on:, payer:, options:, today: Date.current)
          parts = document_parts(account.config["beneficiary_document"])
          address = (payer[:address] || {}).transform_keys(&:to_s)
          raise Error, I18n.t("payments.providers.bradesco.errors.payer_address") unless address.values_at("street", "district", "city", "state").all?(&:present?)

          payer_document = digits(payer[:document])
          zip = digits(address["zip"]).rjust(8, "0")
          fine = options[:fine_percent].to_d
          interest = options[:interest_percent].to_d
          discount = options[:discount_percent].to_d
          message = text(options[:message], 80)
          {
            "debitoAutomatico" => "N", "nuCPFCNPJ" => parts[:root], "filialCPFCNPJ" => parts[:branch], "ctrlCPFCNPJ" => parts[:control],
            "idProduto" => wallet(account), "nuNegociacao" => negotiation18(account), "nuTitulo" => our_number.to_i, "nuCliente" => identifier(custom_id, 15),
            "dtEmissaoTitulo" => dotted(today), "dtVencimentoTitulo" => dotted(due_on), "tpVencimento" => 0, "indicadorMoeda" => 1,
            "vlNominalTitulo" => reais(amount_cents), "cdEspecieTitulo" => SPECIES.fetch(account.config["species"].to_s, SPECIES["DM"]),
            "tpProtestoAutomaticoNegativacao" => 0, "prazoProtestoAutomaticoNegativacao" => 0, "controleParticipante" => identifier(custom_id, 25),
            "cdPagamentoParcial" => "", "qtdePagamentoParcial" => 0, "tipoPrazoDecursoTres" => options[:write_off_days].to_i,
            # Percentual com até duas casas (C l. 415-448); juros ao mês (C l. 228-232). O "+1" dos dias (C l. 515-520) fica no roteiro de homologação.
            "percentualJuros" => interest.round(2).to_f, "vlJuros" => 0, "qtdeDiasJuros" => interest.positive? ? 1 : 0,
            "percentualMulta" => fine.round(2).to_f, "vlMulta" => 0, "qtdeDiasMulta" => fine.positive? ? 1 : 0,
            "percentualDesconto1" => discount.round(2).to_f, "vlDesconto1" => 0, "dataLimiteDesconto1" => discount.positive? ? dotted(due_on) : "",
            "percentualDesconto2" => 0, "vlDesconto2" => 0, "dataLimiteDesconto2" => "", "percentualDesconto3" => 0, "vlDesconto3" => 0, "dataLimiteDesconto3" => "",
            "percentualBonificacao" => 0, "vlBonificacao" => 0, "dtLimiteBonificacao" => "", "vlAbatimento" => 0, "vlIOF" => 0,
            "nomePagador" => text(payer[:name], 40), "logradouroPagador" => text(address["street"], 40), "nuLogradouroPagador" => text(address["number"], 10).presence || "SN",
            "complementoLogradouroPagador" => text(address["complement"], 30), "cepPagador" => zip[0, 5].to_i, "complementoCepPagador" => zip[5, 3].to_i,
            "bairroPagador" => text(address["district"], 20), "municipioPagador" => text(address["city"], 40), "ufPagador" => text(address["state"], 2),
            "cdIndCpfcnpjPagador" => payer_document.length == 14 ? 2 : 1, "nuCpfcnpjPagador" => payer_document.to_i, "endEletronicoPagador" => "",
            "nomeSacadorAvalista" => "", "logradouroSacadorAvalista" => "", "nuLogradouroSacadorAvalista" => "", "complementoLogradouroSacadorAvalista" => "",
            "cepSacadorAvalista" => 0, "complementoCepSacadorAvalista" => 0, "bairroSacadorAvalista" => "", "municipioSacadorAvalista" => "", "ufSacadorAvalista" => "",
            "cdIndCpfcnpjSacadorAvalista" => 0, "nuCpfcnpjSacadorAvalista" => 0, "enderecoSacadorAvalista" => "",
            "listaMsgs" => message.present? ? [ { "mensagem" => message } ] : []
          }
        end

        # Resposta do registro (C l. 1359-1494): o nosso número, a linha digitável e o valor em centavos.
        def registration_issued(data, our_number:, fallback_amount:, fallback_due:)
          line = data["linhaDigitavel"].to_s.squish.presence or raise Error, I18n.t("payments.providers.bradesco.errors.no_digitable_line")
          Issued.new(external_id: Payloads.our_number(data["nuTituloGerado"].presence || our_number), status: status_of(data["codStatus10"]),
                     amount_cents: data["vlTitulo"].is_a?(Integer) ? data["vlTitulo"] : fallback_amount,
                     due_on: date(data["dtVencimento"]) || date(data["dtVencimentoBoleto"]) || fallback_due, digitable_line: line)
        end

        # ---- Consulta, baixa e alteração (C l. 2148-3437) ----

        def lookup_body(account, our_number) = contract(account).merge("nossoNumero" => our_number.to_i, "sequencia" => 0, "status" => 0)

        def write_off_body(account, our_number) = contract(account).merge("nossoNumero" => our_number.to_i, "sequencia" => 0, "codigoBaixa" => WRITE_OFF_CODE)

        # Só o vencimento muda; os campos que a tabela marca como obrigatórios vão com o valor fixo dela e o resto com zero (C l. 2473-2620). Se o zero
        # zera ou mantém (contradição 11 da leitura), a homologação diz.
        def due_date_body(account, our_number, due_on)
          contract(account).merge("nossoNumero" => our_number.to_i,
                                  "dadosTitulo" => { "vencimento" => { "dataVencimento" => compact_date(due_on), "tipoVencimento" => 0 },
                                                     "protesto" => { "codInstrucaoProtesto" => 1, "qtdeDiasProtesto" => 0 }, "decurso" => { "codDecursoPrazo" => 1, "diasDecursoPrazo" => 0 },
                                                     "abatimento" => { "tipoAbatimento" => 1, "valorAbatimento" => 0 }, "codigoMulta" => 2, "codigoNegativacao" => 1,
                                                     "indicadorAvisoSacado" => "0" })
        end

        # A consulta de um título no nosso vocabulário. O valor do título vem em centavos (`valMoeda`); o pago (`vlrPagto`) vem como decimal no exemplo
        # (C l. 3424-3425) e a homologação confirma.
        def lookup_issued(data, external_id)
          title = data["titulo"].is_a?(Hash) ? data["titulo"] : data
          raise Error, I18n.t("payments.providers.bradesco.errors.not_found") if title.blank?

          status = status_of(title["codStatus"])
          paid = cents(title["vlrPagto"])
          Issued.new(external_id: our_number(external_id), status: status, amount_cents: (title["valMoeda"].to_i.nonzero? || cents(title["valorMoedaBol"]).nonzero?),
                     due_on: date(title["dataVencto"]) || date(title["dataVenctoBol"]), digitable_line: title["linhaDig"].to_s.squish.presence,
                     paid_cents: (status == "paid" && paid.positive? ? paid : nil))
        end

        def status_of(code)
          code = code.to_i
          if PAID.include?(code) then "paid"
          elsif EXPIRED.include?(code) then "expired"
          elsif CANCELED.include?(code) then "canceled"
          else "active"
          end
        end

        # ---- Webhook e lista de liquidados (C l. 3796-4269, 6456-6790) ----

        def webhook_body(account, url)
          parts = document_parts(account.config["beneficiary_document"])
          { "documento" => { "cpfCnpj" => parts[:root].to_s, "filial" => parts[:branch].to_s, "controle" => parts[:control].to_s }, "versaoLayout" => "1",
            "tipoCadastro" => "I", "utilizaWebhook" => "S", "urlEnvio" => url, "tipoAviso" => "1" }
        end

        # O mesmo pagamento tem o mesmo identificador pelo webhook e pela lista (R284b): o aviso do banco não tem identificador próprio.
        def boleto_event_id(our_number, paid_on, paid_cents) = "boleto:#{our_number(our_number)}:#{paid_on&.iso8601}:#{paid_cents}"

        # Aviso de pagamento (só pagamento, `tipoEvento` "P"; C l. 6736-6790): valores decimais em texto, datas ISO, hora HHMMSS.
        def boleto_paid_notification(data)
          return unless data["tipoEvento"].to_s.upcase == "P"

          paid_on = date(data["dataPagamento"])
          paid = cents(data["valorPagamento"].to_s)
          hour = data["horaPagamento"].to_s.rjust(6, "0")
          occurred = paid_on && Time.zone.local(paid_on.year, paid_on.month, paid_on.day, hour[0, 2].to_i.clamp(0, 23), hour[2, 2].to_i.clamp(0, 59), hour[4, 2].to_i.clamp(0, 59))
          Notification.new(event_id: boleto_event_id(data["nossoNumero"], paid_on, paid), kind: :paid, external_id: our_number(data["nossoNumero"]),
                           amount_cents: paid.nonzero?, occurred_at: occurred)
        end

        # Liquidados por data de pagamento (D-1, no máximo 60 dias), página a página (`paginaAnterior` = a página que voltou).
        def liquidated_list_body(account, from:, to:, page:)
          contract(account).merge("dataMovimentoDe" => 0, "dataMovimentoAte" => 0, "dataPagamentoDe" => compact_date(from), "dataPagamentoAte" => compact_date(to),
                                  "origemPagamento" => 0, "valorTituloDe" => 0, "valorTituloAte" => 0, "paginaAnterior" => page)
        end

        def liquidated_notification(title)
          return unless title.is_a?(Hash) && title["nossoNumero"].present?

          paid_on = date(title["dataPagamento"])
          paid = cents(title["valorPagamento"])
          Notification.new(event_id: boleto_event_id(title["nossoNumero"], paid_on, paid), kind: :paid, external_id: our_number(title["nossoNumero"]),
                           amount_cents: paid.nonzero?, occurred_at: paid_on&.in_time_zone)
        end

        # O exemplo usa `indMaisPagina`; a tabela, `IndicadorMaisPaginas` (C l. 3966-3970, 4065-4066).
        def more_pages?(data) = (data["indMaisPagina"] || data["IndicadorMaisPaginas"]).to_s.strip.upcase == "S"

        # ---- Respostas ----

        # Lê a resposta da API de cobrança. O registro tem códigos próprios ("Status-Header", C l. 1497-1700), cujo lugar na resposta o manual não diz:
        # procura no cabeçalho e no corpo. As outras APIs repetem o status no corpo, com `mensagem` e `causa` "CBTTnnnn - TEXTO".
        def read_boleto(response, registration: false, not_found_ok: false)
          raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: true) if response.status == 429 || response.status >= 500

          json = (JSON.parse(response.body.to_s) rescue nil) || {}
          raise Error, I18n.t("payments.providers.bradesco.errors.refused", detail: short(json)) if [ 401, 403 ].include?(response.status)

          registration ? read_registration(response, json) : read_other(response, json, not_found_ok)
        end

        def read_registration(response, json)
          return json if json["nuTituloGerado"].to_i.positive? && json["linhaDigitavel"].present?

          code = (response.headers || {}).transform_keys(&:to_s).transform_keys(&:downcase)["status-header"] || json["codigo"] || json["cdRetorno"] || json["status"]
          code = Integer(code.to_s, exception: false)
          return :already_registered if code == REGISTRATION_TAKEN || short(json).match?(/t[ií]tulo j[aá] cadastrado/i)
          raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: true) if REGISTRATION_UNAVAILABLE.include?(code)

          raise Error, I18n.t("payments.providers.bradesco.errors.refused", detail: short(json))
        end

        def read_other(response, json, not_found_ok)
          cause = json["causa"].to_s
          return {} if not_found_ok && cause.include?(NOT_FOUND_CAUSE)
          raise NetworkError.new(I18n.t("payments.providers.bradesco.errors.unavailable"), retry_safe: true) if UNAVAILABLE_CAUSES.any? { |code| cause.include?(code) }

          status = Integer(json["status"].to_s, exception: false)
          return json if (200..299).cover?(response.status) && (status.nil? || (200..299).cover?(status))

          raise Error, I18n.t("payments.providers.bradesco.errors.refused", detail: short(json))
        end

        # Mensagem curta e segura: a causa ou a mensagem do banco, nunca o corpo inteiro.
        def short(json)
          return "resposta de erro do fornecedor" unless json.is_a?(Hash)

          errors = Array(json["listaErros"]).filter_map { |item| item["descricaoErro"] if item.is_a?(Hash) }
          text = [ json["causa"].presence || json["mensagem"].presence || json["descricao"].presence, *errors ].compact.join("; ")
          text.to_s.gsub(/[[:cntrl:]]/, " ").squish.first(200).presence || "resposta de erro do fornecedor"
        end

        # ---- Pix do Bradesco ----

        # 412 com "identificador da transação já está em uso" (4001, P l. 1080): a cobrança já existe e se consulta.
        def txid_in_use?(body) = body.to_s.match?(/4001|j[aá] est[aá] em uso/i)

        # A imagem do `cobv-emv` (`base64`, P l. 5046-5048): o manual não diz se é PNG nem se vem com prefixo `data:`. Só PNG válido serve; o resto faz o
        # QR Code ser gerado aqui do "copia e cola" (R273).
        def png_of(value)
          text = value.to_s.sub(%r{\Adata:image/png;base64,}, "").gsub(/\s/, "")
          return if text.empty?

          bytes = Base64.strict_decode64(text)
          bytes if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
        rescue ArgumentError
          nil
        end

        # ---- Ficha de compensação (R284e) ----

        def slip_attributes(account, issued, instrument)
          config = account.config
          number = our_number(issued.external_id)
          wallet_code = wallet(account).to_s.rjust(2, "0")
          instructions = []
          instructions << config["message"].to_s.first(80) if config["message"].present?
          instructions << "Após o vencimento, multa de #{format('%.2f', config['fine_percent'].to_d).tr('.', ',')}%." if config["fine_percent"].to_d.positive?
          instructions << "Após o vencimento, juros de #{format('%.2f', config['interest_percent'].to_d).tr('.', ',')}% ao mês." if config["interest_percent"].to_d.positive?
          address = (instrument&.payer_address || {}).transform_keys(&:to_s)
          { bank_name: "Bradesco", bank_code: "237-2", digitable_line: issued.digitable_line.to_s, due_on: instrument&.due_on || issued.due_on,
            amount_cents: instrument&.amount_cents || issued.amount_cents, beneficiary_name: config["beneficiary_name"].to_s,
            beneficiary_document: digits(config["beneficiary_document"]),
            agency_code: "#{agency(account)}-#{config['agency_digit']}/#{account_number(account)}-#{config['account_digit']}",
            wallet_our_number: "#{wallet_code} / #{number}-#{Febraban.bradesco_our_number_digit(wallet_code, number)}",
            document_number: instrument&.custom_id.to_s.last(15), species: config["species"].to_s, issued_on: (instrument&.issued_at || Time.current).to_date,
            payer_name: instrument&.payer_name.to_s, payer_document: instrument&.payer_document.to_s,
            payer_address: [ [ address["street"], address["number"], address["complement"] ].compact_blank.join(", "),
                             [ address["district"], address["city"], address["state"] ].compact_blank.join(" - "), address["zip"] ].compact_blank.join(" | "),
            payment_place: "Pagável preferencialmente na rede Bradesco ou no Bradesco expresso", instructions: instructions,
            free_field_check: ->(free) { free.agency == agency(account) && free.wallet == wallet_code && free.our_number == number && free.account == account_number(account) } }
        end
      end
    end
  end
end
