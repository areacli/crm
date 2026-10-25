# Texto dos critérios de um segmento, numa linha (R148), e valores dos campos do formulário.
module SegmentsHelper
  def segment_criteria_summary(entry)
    entry = entry.respond_to?(:criteria) ? entry.criteria : entry
    parts = []
    parts << range_text("Atraso", entry, :overdue_days, " dias")
    parts << range_text("Saldo", entry, :balance_cents) { |value| money(value) }
    parts << range_text("Títulos vencidos", entry, :overdue_bills)
    parts << range_text("Valor vencido", entry, :overdue_percent, "%")
    parts << range_text("Clientes no contrato", entry, :customers)
    parts << range_text("Idade do contrato", entry, :age_days, " dias")
    parts << "Tipo: #{t("segments.person_types.#{entry[:person_type]}")}" if entry[:person_type].present?
    parts << "Produto: #{Array(entry[:products]).join(', ')}" if Array(entry[:products]).any?
    parts << "Já quebrou acordo: #{t("segments.broke_agreement.#{entry[:broke_agreement]}")}" if entry[:broke_agreement].present?
    parts.compact.presence&.join(" · ") || "Sem critérios"
  end

  # Valor mostrado no campo: o que a pessoa digitou (se houve erro) ou o gravado.
  def segment_field_value(segment, raw, column)
    return raw[column] if raw&.key?(column)

    value = segment[column]
    value.nil? ? "" : (column.to_s.end_with?("balance_cents") ? Money.format(value) : value)
  end

  def segment_products_value(segment, raw) = raw&.key?(:products) ? raw[:products] : segment.products.join(", ")

  private
    def range_text(label, entry, name, suffix = "")
      low = entry[:"min_#{name}"]
      high = entry[:"max_#{name}"]
      return if low.nil? && high.nil?

      format = block_given? ? ->(value) { yield(value) } : ->(value) { value.to_s }
      text = if low && high then "de #{format.call(low)} a #{format.call(high)}#{suffix}"
      elsif low then "a partir de #{format.call(low)}#{suffix}"
      else "até #{format.call(high)}#{suffix}"
      end
      "#{label} #{text}"
    end
end
