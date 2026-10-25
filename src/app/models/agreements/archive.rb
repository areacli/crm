require "csv"

module Agreements
  # Arquivo de acordos (11, R244, DA13, DA37): o que o credor precisa para emitir a entrada e as parcelas e parar de cobrar os originais. Quatro tipos de linha num CSV só
  # (separador ponto e vírgula, valores em centavos): `divida` (cada título original, com a base e o desconto por componente), `acordo`, `titulo_de_acordo` (com o percentual de
  # multa, a taxa e a convenção dos juros de atraso, o desconto por dia de antecipação e os parâmetros de correção e honorários) e `evento`. Formas: novidades desde a última
  # exportação manual, completo, e as novidades do dia, que o CRM gera todo dia e não mudam o marco da exportação manual.
  class Archive
    HEADER = %w[tipo acordo titulo contrato documento nome data situacao valor entrada parcelas metodo taxa_mensal taxa_efetiva_anual forma_da_quebra credito_usado valor_liquido
                vencimento juros_parcelamento amortizacao multa_pct taxa_juros_atraso convencao_juros juros_dia_centavos desconto_antecipacao_dia indice_correcao honorarios_pct
                base_principal base_correcao base_multa base_juros base_honorarios desconto_principal desconto_correcao desconto_multa desconto_juros desconto_honorarios
                valor_no_acordo evento detalhe].freeze

    EVENT_NAMES = { "accepted" => "aceito", "effectuated" => "efetivado", "settlement_calculated" => "quitacao calculada", "settled" => "quitado", "broken" => "quebrado",
                    "reactivated" => "reativado", "canceled" => "cancelado", "reversion_opened" => "em reversao", "reversion_desisted" => "reversao desistida",
                    "reversal_title" => "titulo novo", "reopened" => "quitado reaberto", "renegotiated_reopened" => "renegociado reaberto", "renegotiated" => "acordo anterior renegociado",
                    "reversal_waiting" => "estorno a espera do gestor", "reversal_decided" => "decisao do gestor sobre estorno" }.freeze

    def initialize(tenant) = @tenant = tenant

    # Gera o arquivo, registra a exportação e devolve o registro. `user` vazio é a geração do dia.
    def export!(form, user: nil, today: Date.current)
      events = events_for(form, today)
      agreements = agreements_for(form, events)
      text = csv(agreements, events)
      record = AgreementExport.create!(tenant: @tenant, user: user, form: form, last_event_id: (form == "daily" ? marker : (events.map(&:id).max || marker)), lines: text.lines.size - 1,
                                       created_at: Time.current)
      FileUtils.mkdir_p(AgreementExport::DIRECTORY)
      File.write(record.path_for_write, text)
      record.update!(file_name: record.default_file_name)
      record
    end

    private
      def marker = AgreementExport.where(tenant_id: @tenant.id).manual.maximum(:last_event_id).to_i

      def accepted_events = AgreementEvent.joins(:agreement).where(tenant_id: @tenant.id, kind: EVENT_NAMES.keys).where.not(agreements: { accepted_at: nil }).includes(:agreement).order(:id)

      def events_for(form, today)
        case form
        when "news" then accepted_events.where("agreement_events.id > ?", marker).to_a
        when "daily" then accepted_events.where(agreement_events: { occurred_at: today.in_time_zone.beginning_of_day.. }).to_a
        else accepted_events.to_a
        end
      end

      def agreements_for(form, events)
        return Agreement.where(tenant_id: @tenant.id).where.not(accepted_at: nil).order(:id).to_a if form == "full"

        Agreement.where(id: events.map(&:agreement_id).uniq).order(:id).to_a
      end

      def csv(agreements, events)
        CSV.generate(col_sep: ";") do |out|
          out << HEADER
          agreements.each do |agreement|
            out << row(tipo: "acordo", **agreement_columns(agreement))
            agreement.agreement_bills.includes(:bill, :contract).sort_by(&:bill_id).each { |item| out << row(tipo: "divida", **debt_columns(agreement, item)) }
            titles(agreement).each { |bill| out << row(tipo: "titulo_de_acordo", **title_columns(agreement, bill)) }
          end
          events.each { |event| out << row(tipo: "evento", **event_columns(event)) }
        end
      end

      def row(**values) = HEADER.map { |column| values[column.to_sym] }

      def agreement_columns(agreement)
        { acordo: agreement.number, documento: agreement.customer.document, nome: agreement.customer.name, data: agreement.accepted_at&.to_date&.iso8601, situacao: agreement.state,
          valor: agreement.value_cents, entrada: agreement.down_payment_cents, parcelas: agreement.installments_count, metodo: agreement.installment_method, taxa_mensal: agreement.rate_pct.to_s("F"),
          taxa_efetiva_anual: agreement.effective_annual_pct.to_s("F"), forma_da_quebra: agreement.frozen_policy("break_form"), credito_usado: agreement.credit_cents + agreement.credit_down_cents,
          valor_liquido: agreement.net_cents }
      end

      def debt_columns(agreement, item)
        base = item.base
        discount = item.discount
        { acordo: agreement.number, titulo: item.bill.number, contrato: item.contract.code, valor_no_acordo: item.value_cents,
          base_principal: base["principal"].to_i, base_correcao: base["correction"].to_i, base_multa: base["fine"].to_i, base_juros: base["interest"].to_i, base_honorarios: base["fees"].to_i,
          desconto_principal: discount["principal"].to_i, desconto_correcao: discount["correction"].to_i, desconto_multa: discount["fine"].to_i, desconto_juros: discount["interest"].to_i,
          desconto_honorarios: discount["fees"].to_i }
      end

      def titles(agreement) = agreement.titles.reload.to_a + agreement.reversal_titles.to_a

      # A situação do título de acordo no arquivo (R244): a cobrar, pago, cancelado, renegociado, ou "a cobrar após encerramento" quando o acordo terminou com o título em aberto.
      def title_situation(agreement, bill)
        return (bill.paid? ? "pago" : bill.canceled? ? "cancelado" : bill.renegotiated? ? "renegociado" : "titulo de estorno") if bill.kind_reversal?

        case bill.status
        when "paid" then "pago"
        when "canceled" then "cancelado"
        when "renegotiated" then "renegociado"
        when "scheduled" then "a cobrar"
        else agreement.state_settled? || agreement.state_renegotiated? ? "a cobrar apos encerramento" : "a cobrar"
        end
      end

      def title_columns(agreement, bill)
        rule = agreement.terms.dig("parameters", "late_rule") || {}
        period = bill.composition["period_days"].to_i
        { acordo: agreement.number, titulo: bill.number, contrato: bill.contract.code, data: bill.created_at.to_date.iso8601, situacao: title_situation(agreement, bill), valor: bill.amount_cents,
          vencimento: bill.due_date.iso8601, juros_parcelamento: bill.composition["installment_interest"].to_i, amortizacao: bill.amount_cents - bill.composition["installment_interest"].to_i,
          multa_pct: (rule["fine"].to_f * 100).round(4), taxa_juros_atraso: (rule["rate"].to_f * 100).round(4), convencao_juros: rule["convention"],
          juros_dia_centavos: (rule["convention"] == "thirty" ? (bill.composition.fetch("items", []).sum { |item| %w[principal correction].include?(item["component"]) ? item["cents"] : 0 } * rule["rate"].to_f / 30).round(4) : nil),
          desconto_antecipacao_dia: (period.positive? ? (bill.composition["installment_interest"].to_f / period).round(4) : nil), indice_correcao: rule["index"], honorarios_pct: (rule["fees"].to_f * 100).round(4) }
      end

      def event_columns(event)
        agreement = event.agreement
        detail =
          case event.kind
          when "effectuated" then "originais: #{agreement.agreement_bills.includes(:bill).map { |item| item.bill.number }.sort.join(',')}"
          when "settlement_calculated" then "valor #{event.data['amount_cents']} ate #{event.data['on']}"
          when "canceled" then [ event.data["reason"], ("voltam a ser cobrados: #{agreement.agreement_bills.includes(:bill).map { |item| item.bill.number }.sort.join(',')}" if agreement.state_canceled?) ].compact.join("; ")
          when "broken" then "forma: #{event.data['form'] || 'antes da efetivacao'}"
          when "reversal_title" then "titulo: #{event.data['number']} valor #{event.data['amount_cents']}"
          when "reversal_waiting" then "pagamento #{event.data['payment']} valor #{event.data['amount_cents']}"
          when "reversal_decided" then "#{event.data['decision']}: #{event.data['note']}"
          end
        { acordo: agreement.number, data: event.occurred_at.to_date.iso8601, evento: EVENT_NAMES.fetch(event.kind), detalhe: detail }
      end
  end
end
