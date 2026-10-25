module Titular
  # Exportação dos dados de um cliente de um credor (07, R127, R127a, R128): um dicionário único, que vira a página para imprimir e o JSON.
  # O conteúdo não é guardado; só o fato de ter sido exportado (R129). Dos outros clientes dos contratos, apenas a quantidade.
  class Exporter
    def initialize(customer) = @customer = customer

    def to_h
      {
        credor: @customer.tenant.display_name, exportado_em: Time.current.iso8601, anonimizado: @customer.anonymized?,
        cliente: { nome: @customer.name, documento: (@customer.anonymized? ? nil : @customer.formatted_document), anonimizado_em: @customer.anonymized_at&.iso8601 },
        contatos: contacts, contratos: contracts, titulos: bills, pagamentos: payments, estornos: reversals, creditos: credits,
        divergencias_de_valor: discrepancies, acionamentos: attempts, historico: history
      }
    end

    private
      def contacts
        @customer.contacts.order(:id).map do |c|
          { tipo: c.kind, contato: c.value, situacao: c.status, origem: c.origin, motivo: c.reason, pedido_nao_perturbe_em: c.do_not_disturb_on&.iso8601, desde: c.created_at.iso8601 }
        end
      end

      def contract_ids = @contract_ids ||= @customer.contract_ids

      def contracts
        others = ContractCustomer.where(contract_id: contract_ids).where.not(customer_id: @customer.id).group(:contract_id).count
        credit = Credit.where(contract_id: contract_ids).group(:contract_id).sum(:amount_cents)
        @customer.contract_customers.includes(:contract).map do |link|
          { codigo: link.contract.code, papeis: link.roles, outros_clientes: others.fetch(link.contract_id, 0), credito_do_contrato_centavos: credit.fetch(link.contract_id, 0) }
        end
      end

      def bill_scope = Bill.where(customer_id: @customer.id)

      def bills
        versions = BillValueVersion.where(bill_id: bill_scope.select(:id)).order(:id).group_by(&:bill_id)
        bill_scope.includes(:contract).order(:due_date, :id).map do |b|
          { numero: b.number, contrato: b.contract.code, vencimento: b.due_date.iso8601, valor_centavos: b.amount_cents, pago_centavos: b.paid_cents, situacao: b.status,
            pago_em: b.paid_on&.iso8601, descricao: b.description, produto: b.product,
            versoes_do_valor: versions.fetch(b.id, []).map { |v| { valor_centavos: v.amount_cents, em: v.created_at.iso8601 } } }
        end
      end

      def payment_scope
        Payment.where(tenant_id: @customer.tenant_id).where("bill_id in (?) or (bill_id is null and document = ?)", bill_scope.select(:id), @customer.document)
      end

      def payments
        payment_scope.includes(:channel, :bill).order(:paid_on, :id).map do |p|
          { identificador: p.identifier, canal: p.channel.description, titulo: p.bill&.number, pago_em: p.paid_on.iso8601, valor_centavos: p.amount_cents, meio: p.payment_method,
            situacao: p.status, aplicado_centavos: p.applied_cents, credito_centavos: p.credit_cents, estornado_centavos: p.reversed_cents }
        end
      end

      def reversals
        PaymentReversal.where(payment_id: payment_scope.select(:id)).order(:reversed_on, :id).map do |r|
          { identificador: r.identifier, estornado_em: r.reversed_on.iso8601, valor_centavos: r.amount_cents, do_credito_centavos: r.from_credit_cents, do_titulo_centavos: r.from_bill_cents, motivo: r.reason }
        end
      end

      # A transferência aparece como "crédito transferido a outro contrato", sem identificar o outro (07, R127).
      def credits
        Credit.where(contract_id: contract_ids).includes(:contract).order(:occurred_at, :id).map do |c|
          { contrato: c.contract.code, em: c.occurred_at.iso8601, tipo: c.kind, motivo: c.reason, valor_centavos: c.amount_cents, nota: c.note,
            descricao: (I18n.t("titular.export.credit_transferred") if c.because_transfer?) }.compact
        end
      end

      def discrepancies
        ValueDiscrepancy.where(bill_id: bill_scope.select(:id)).includes(:bill).order(:id).map do |d|
          { titulo: d.bill.number, valor_anterior_centavos: d.previous_cents, valor_informado_centavos: d.reported_cents, efeito: d.effect, situacao: d.status, nota: d.note }
        end
      end

      def attempts
        @customer.contact_attempts.includes(:result, :user, :contract).order(:contacted_at, :id).map do |a|
          { em: a.contacted_at.iso8601, canal: a.channel, resultado: a.result.name, contrato: a.contract&.code, contato_usado: a.contact_used, texto: a.text, registrado_por: a.user&.name }
        end
      end

      def history
        attempt_ids = @customer.contact_attempts.select(:id)
        contact_ids = @customer.contacts.select(:id)
        Change.where(tenant_id: @customer.tenant_id).where(
          "(subject_type = 'customer' and subject_id = :c) or (subject_type = 'customer_contact' and subject_id in (:k)) or " \
          "(subject_type = 'contact_attempt' and subject_id in (:a)) or (subject_type = 'bill' and subject_id in (:b))",
          c: @customer.id, k: contact_ids, a: attempt_ids, b: bill_scope.select(:id)
        ).includes(:user).order(:occurred_at, :id).map do |c|
          { em: c.occurred_at.iso8601, tipo: c.subject_type, evento: c.event, campo: c.field, antes: c.before, depois: c.after, motivo: c.note, por: c.user&.name }
        end
      end
  end
end
