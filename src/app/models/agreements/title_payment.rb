module Agreements
  # O que um pagamento faz num título de acordo (11, R226, R227, R228a): cobre, na ordem, os encargos de atraso, os juros do parcelamento e a composição herdada. Valor igual
  # ou maior que o devido quita o título (o excedente é do chamador, DA9); o estado final "quitado" do arquivo ou a tolerância de valor dos títulos de acordo dão
  # o título por pago com a diferença registrada como abatimento; menor que isso, o título fica em aberto pelo resto (a política de pagamento parcial da 03 não vale
  # para título de acordo). Pagamento antes do vencimento tem o desconto dos juros do parcelamento (DA35). Função pura sobre o `Ledger`.
  module TitlePayment
    # `parts`: o que o dinheiro cobriu; `abatements`: [[tipo, partes]] (a diferença dada por paga e o desconto da antecipação); `excess`: o que passou do devido;
    # `settled`: se o título ficou pago; `due`: o devido na data.
    Result = Data.define(:parts, :abatements, :excess, :settled, :due) do
      def applied = parts.values.sum

      # O que entra no pago do título (a face): o dinheiro mais os abatimentos, sem os encargos de atraso.
      def face_covered = parts.sum { |component, cents| component == "late" ? 0 : cents } + abatements.sum { |_, items| items.sum { |component, cents| component == "late" ? 0 : cents } }
    end

    module_function

    # `tolerance`: a tolerância de valor ({kind, value}, R228a) sobre o devido; `final_state`: "settled" quando o arquivo traz "quitado" (PG-3).
    def call(ledger, date:, amount:, tolerance: nil, final_state: nil)
      due = ledger.due(date)
      total = due.total
      tolerance = Policies.tolerance_of(tolerance, total)
      return Result.new({}, [], amount, false, due) if total.zero?

      early = early_abatement(due)
      if amount >= total
        Result.new(due.parts, early, amount - total, true, due)
      elsif final_state == "settled"
        abated(due, amount, "creditor", early)
      elsif total - amount <= tolerance
        abated(due, amount, "tolerance", early)
      else
        Result.new(distribute(due.parts, amount), [], 0, false, due)
      end
    end

    # Os componentes cobertos pelo dinheiro, na ordem de pagamento dos títulos de acordo.
    def distribute(due, amount)
      ORDER.each_with_object({}) do |component, parts|
        part = [ amount, due.fetch(component, 0) ].min
        next unless part.positive?

        parts[component] = part
        amount -= part
      end
    end

    # Título pago com abatimento: o dinheiro cobre os componentes na ordem e o que falta, a partir do principal, é a diferença dada por paga (R228a).
    def abated(due, amount, kind, early)
      parts = distribute(due.parts, amount)
      left = due.parts.to_h { |component, cents| [ component, cents - parts.fetch(component, 0) ] }.select { |_, cents| cents.positive? }
      Result.new(parts, early + [ [ kind, left ] ], 0, true, due)
    end

    def early_abatement(due) = due.early.positive? ? [ [ "early", { "installment_interest" => due.early } ] ] : []
  end
end
