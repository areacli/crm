module Payments
  # Baixa o pagamento de um evento de webhook já autenticado e guardado. Passa pelas mesmas regras do arquivo (validação, unicidade
  # por canal + identificador, pendente quando o título não está na carteira, políticas do credor): a linha entra na preparação e o
  # `Processor` a aplica, numa transação travada pelo mesmo bloqueio por credor das importações. O resultado fica numa importação
  # de pagamentos já confirmada (origem "webhook"), para o registro de quem, quando e o que mudou.
  class WebhookProcessor
    Sql = Portfolio::Sql

    def run(event)
      return unless event.received?

      channel = event.channel
      parsed = Gateway.for(channel.webhook_adapter).event(event.payload)
      return finish(event, :ignored, "evento #{parsed.kind.presence || 'sem tipo'} não é de pagamento recebido") unless parsed.payment
      return finish(event, :rejected, "canal desativado") unless channel.active?

      row, reason = validate(channel, parsed.payment)
      return finish(event, :rejected, reason) unless row

      ApplicationRecord.transaction do
        Sql.execute("select pg_advisory_xact_lock(1, ?)", channel.tenant_id)
        if Payment.exists?(tenant_id: channel.tenant_id, channel_id: channel.id, identifier: row.identifier)
          finish(event, :ignored, "pagamento já registrado")
        else
          apply(event, channel, row)
        end
      end
      ValuesRecalculationJob.enqueue_for(channel.tenant, reason: "pagamento") if event.reload.applied? # 09, R173: o principal em aberto mudou
    end

    private
      def validate(channel, data)
        paid_on = Date.iso8601(data[:paid_on]) rescue nil
        return [ nil, "data inválida" ] unless paid_on && data[:amount_cents].is_a?(Integer) && data[:amount_cents].positive?

        values = { "canal" => channel.code, "identificador" => data[:identifier], "documento" => data[:document], "titulo" => data[:bill_number],
                   "data_pagamento" => paid_on.strftime("%d/%m/%Y"), "valor" => Money.format(data[:amount_cents]), "meio" => data[:payment_method] }
        PaymentRowValidator.new.validate(Portfolio::CsvFile::Row.new(line: 1, values: values, extra: false, short: false))
      end

      def apply(event, channel, row)
        import = Import.create!(tenant: channel.tenant, kind: :payments, mode: :incremental, status: :confirmed, original_name: "webhook #{event.event_id}",
                                size_bytes: 0, progress_percent: 100, finished_at: Time.current)
        staging = Staging.new(import.id)
        staging.add(row)
        staging.flush
        effect = Processor.new.run(import, commit: true)
        Sql.run("delete from payment_rows where import_id = ?", import.id)
        import.update!(summary: { lines: 1, valid: 1, rejected: 0, ignored: 0, amount_cents: row.amount_cents, amount_formatted: Money.format(row.amount_cents),
                                  confirmed_effect: effect })
        finish(event, :applied, outcome_of(effect))
      end

      def outcome_of(effect)
        if effect[:pending_new].to_i.positive? then "pendente: o título não está na carteira"
        elsif effect[:settled].to_i.positive? then "título quitado"
        elsif effect[:partial].to_i.positive? then "baixa parcial"
        elsif effect[:credits].to_i.positive? then "virou crédito do contrato"
        else "registrado"
        end
      end

      def finish(event, status, outcome)
        event.update!(status: status, outcome: outcome, processed_at: Time.current)
      end
  end
end
