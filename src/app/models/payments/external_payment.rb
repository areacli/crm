module Payments
  # Pagamento e estorno que chegam de fora da planilha (os instrumentos pagos da parte D do incremento 12) entrando pelo MESMO
  # caminho do arquivo: a linha passa pela validação, vai à tabela de preparação e o `Processor` (ou o `ReversalProcessor`) a aplica, numa transação
  # travada pelo mesmo bloqueio por credor das importações, com baixa pelas políticas do credor, encargos por componente, promessas (PRM-) e acordos
  # (ACD-). O resultado fica numa importação já confirmada (origem `label`), que também avisa a tela pelo Action Cable. Idempotente: o pagamento
  # é único por fornecedor, conta (os da integração) e identificador (R48; 03, revisão 12). O evento declara o sistema como a linha da planilha (17, R417c): com mais de um sistema além do CRM e sem o
  # campo, é recusado com o motivo; o instrumento pago é do CRM e vale para o objeto a que foi emitido (R417b).
  class ExternalPayment
    # `status`: applied, ignored (já registrado) ou rejected. `outcome`: o texto para quem acompanha.
    Result = Data.define(:status, :outcome)

    # `data`: identifier, document, bill_number, paid_on (Date ou ISO 8601), amount_cents, payment_method; e, opcionais, system (o nome do sistema),
    # external_bill_id (o id do título nele), own (pagamento de instrumento emitido pelo CRM) e target_bill_id (o título do instrumento).
    # `account`: a integração que emitiu o instrumento; desativada também vale (a troca de fornecedor deixa a anterior conciliando, 16, R373c).
    def pay(account, data, label:)
      row, reason = validate(account, data)
      return Result.new(:rejected, reason) unless row

      result = nil
      ApplicationRecord.transaction do
        TenantLock.acquire(account.tenant_id)
        existing = Payment.find_by(tenant_id: account.tenant_id, provider: row.provider, account_key: row.account_key, identifier: row.identifier)
        result = if existing.nil? then Result.new(:applied, apply(account, row, label))
        # 17, R418: o pendente reenviado com outro sistema troca de sistema e é reavaliado.
        elsif Repoint.due?(existing, row.source_system_id) then Result.new(:applied, repoint(account, existing, row, label))
        else Result.new(:ignored, "pagamento já registrado")
        end
      end
      ValuesRecalculationJob.enqueue_for(account.tenant, reason: "pagamento") if result.status == :applied # 09, R173: o principal em aberto mudou
      result
    end

    # Estorno de um pagamento já registrado (devolução de Pix, reembolso de cartão): reduz do crédito e do título pelas regras de estorno (R60 a R63).
    # `payment`: o pagamento estornado; `identifier`: o do estorno, único com o fornecedor e a conta do pagamento (R61).
    def reverse(payment, identifier:, reversed_on:, amount_cents:, reason:, label:)
      return Result.new(:rejected, "valor inválido") unless amount_cents.is_a?(Integer) && amount_cents.positive?

      identity = { tenant_id: payment.tenant_id, provider: payment.provider, account_key: payment.account_key }
      return Result.new(:ignored, "estorno já registrado") if PaymentReversal.exists?(**identity, identifier: identifier)

      row = ReversalRowValidator::ParsedRow.new(line: 1, payment_method: payment.payment_method, provider: payment.provider, provider_name: payment.provider_name,
                                                account_key: payment.account_key, account_code: payment.account_code,
                                                payment_identifier: payment.identifier, identifier: identifier.to_s.first(200), paid_on: reversed_on.to_date,
                                                amount_cents: amount_cents, reason: reason.to_s.first(300).presence, source_system_id: nil)
      ApplicationRecord.transaction do
        TenantLock.acquire(payment.tenant_id)
        import = confirmed_import(payment.tenant, :reversals, label)
        stage(import, row)
        effect = ReversalProcessor.new.run(import, commit: true)
        PaymentRow.where(import_id: import.id).delete_all
        import.update!(summary: { lines: 1, valid: 1, rejected: 0, ignored: 0, amount_cents: amount_cents, amount_formatted: Money.format(amount_cents), confirmed_effect: effect })
      end
      ValuesRecalculationJob.enqueue_for(payment.tenant, reason: "estorno")
      Result.new(:applied, "estorno registrado")
    end

    private
      def validate(account, data)
        paid_on = data[:paid_on].is_a?(Date) ? data[:paid_on] : (Date.iso8601(data[:paid_on].to_s) rescue nil)
        return [ nil, "data inválida" ] unless paid_on && data[:amount_cents].is_a?(Integer) && data[:amount_cents].positive?

        values = { "fornecedor" => account.provider, "conta" => account.account_code, "identificador" => data[:identifier], "documento" => data[:document], "titulo" => data[:bill_number], "meio" => data[:payment_method],
                   "sistema" => data[:system], "id_titulo" => data[:external_bill_id] }
        PaymentRowValidator.new(Systems.new(account.tenant_id)).validate(RowDecoder.new.from_event(position: 1, values: values, paid_on: paid_on, amount_cents: data[:amount_cents]),
                                                                         own: data[:own] == true, target_bill_id: data[:target_bill_id])
      end

      # O pendente passa ao sistema do evento e o fluxo o reavalia lá: a importação registra a troca, sem pagamento novo.
      def repoint(account, payment, row, label)
        import = confirmed_import(account.tenant, :payments, label)
        Repoint.move(payment, Systems.new(account.tenant_id).find(row.source_system_id), row.external_bill_id, row.bill_number, import: import)
        PaymentStream.prepare(import)
        effect = Processor.new.run(import, commit: true)
        PaymentRow.where(import_id: import.id).delete_all
        import.update!(summary: { lines: 1, valid: 0, rejected: 0, ignored: 0, repointed: 1, amount_cents: 0, amount_formatted: Money.format(0), confirmed_effect: effect })
        "sistema do pagamento pendente trocado: #{payment.reload.pending? ? 'continua pendente' : 'aplicado'}"
      end

      def apply(account, row, label)
        import = confirmed_import(account.tenant, :payments, label)
        stage(import, row)
        effect = Processor.new.run(import, commit: true)
        PaymentRow.where(import_id: import.id).delete_all
        import.update!(summary: { lines: 1, valid: 1, rejected: 0, ignored: 0, amount_cents: row.amount_cents, amount_formatted: Money.format(row.amount_cents),
                                  confirmed_effect: effect })
        outcome_of(effect)
      end

      def confirmed_import(tenant, kind, label)
        Import.create!(tenant: tenant, kind: kind, mode: :incremental, status: :confirmed, original_name: label.to_s.first(200), size_bytes: 0, progress_percent: 100,
                       finished_at: Time.current)
      end

      def stage(import, row)
        staging = Staging.new(import.id)
        staging.add(row)
        staging.flush
        PaymentStream.prepare(import)
      end

      def outcome_of(effect)
        if effect[:pending_new].to_i.positive? then "pendente: o título não está na carteira"
        elsif effect[:settled].to_i.positive? then "título quitado"
        elsif effect[:partial].to_i.positive? then "baixa parcial"
        elsif effect[:credits].to_i.positive? then "virou crédito do contrato"
        else "registrado"
        end
      end
  end
end
