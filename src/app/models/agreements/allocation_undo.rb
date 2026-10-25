module Agreements
  # Desfaz o que um pagamento alocou num título (11, R233, R239, R62): linhas negativas de alocação (e de abatimento, quando o pagamento todo sai do título), na ordem inversa da baixa
  # (principal primeiro). O pago do título cai pelo que a alocação tinha somado e o título pago volta a aberto se o pago deixou de cobrir o valor. O livro continua só de inserção.
  module AllocationUndo
    # Ordem inversa da baixa (R226, R227): a que sai primeiro é a que o pagamento cobriu por último.
    ORDER = %w[principal correction fees fine inherited_late inherited_installment_interest interest installment_interest late].freeze

    # `parts`: { componente => centavos } do dinheiro desfeito; `abated`: [[tipo, componente, centavos]] dos abatimentos desfeitos.
    Result = Data.define(:parts, :abated) do
      def cash = parts.values.sum
    end

    module_function

    # Desfaz até `cents` do dinheiro (ou tudo, sem `cents`) que `payment` alocou em `bill`. `abatements`: desfaz também os abatimentos do pagamento no título (quando o pagamento todo sai dele).
    def call(payment, bill, cents: nil, abatements: false)
      current = PaymentAllocation.where(payment_id: payment.id, bill_id: bill.id).group(:component).sum(:amount_cents).select { |_, value| value.positive? }
      left = cents || current.values.sum
      parts = {}
      ORDER.each do |component|
        part = [ left, current.fetch(component, 0) ].min
        next unless part.positive?

        parts[component] = part
        left -= part
        PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: -part)
      end
      abated = abatements ? undo_abatements(payment, bill) : []
      reduce = parts.sum { |component, value| face?(bill, component) ? value : 0 } + abated.sum { |_, component, value| face?(bill, component) ? value : 0 }
      return Result.new(parts, abated) if reduce.zero?

      paid = [ bill.paid_cents - reduce, 0 ].max
      attributes = { paid_cents: paid }
      attributes.merge!(status: "active", paid_on: nil) if bill.paid? && paid < bill.amount_cents
      bill.update!(attributes)
      Result.new(parts, abated)
    end

    # O abatimento do pagamento no título volta a ser devido (R226): linhas negativas por tipo e componente.
    def undo_abatements(payment, bill)
      Abatement.where(payment_id: payment.id, bill_id: bill.id).group(:kind, :component).sum(:amount_cents).select { |_, value| value.positive? }.map do |(kind, component), value|
        Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: kind, component: component, amount_cents: -value)
        [ kind, component, value ]
      end
    end

    # O que entra no pago do título: no título comum, só o principal (R226); nos de acordo, da quebra e de estorno, a face inteira (sem os encargos de atraso).
    def face?(bill, component) = bill.kind_common? ? component == "principal" : component != "late"
  end
end
