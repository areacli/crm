module Indexes
  # Correção de um índice pelo credor (R145, R146): ajuste do credor sobre o valor global do Banco Central, com motivo obrigatório. Guarda o
  # valor anterior, o novo, quem e quando em `changes`. A permissão 14 já foi conferida pela política no credor.
  class Adjuster
    class Refused < StandardError; end

    VALUE_FORMAT = /\A-?\d{1,5}([.,]\d{1,6})?\z/

    def initialize(user, tenant)
      @user = user
      @tenant = tenant
    end

    def correct(series:, month:, value:, reason:)
      series = series.to_s
      raise Refused, I18n.t("indexes.adjust.series") unless IndexRate::SERIES.include?(series)

      reason = reason.to_s.squish
      raise Refused, I18n.t("indexes.adjust.reason_required") if reason.blank?

      month = parse_month(month)
      number = parse_value(value)
      adjustment = IndexAdjustment.find_by(tenant_id: @tenant.id, series: series, month: month)
      before = adjustment&.value || IndexRate.find_by(series: series, month: month)&.value
      ApplicationRecord.transaction do
        adjustment ||= IndexAdjustment.new(tenant: @tenant, series: series, month: month)
        adjustment.update!(value: number, reason: reason.truncate(300), user: @user, adjusted_at: Time.current)
        log("corrected", adjustment, before, number, reason)
      end
      ValuesRecalculationJob.enqueue_for(@tenant, reason: "índice") # R173: só o credor que corrigiu
      Broadcast.changed
      adjustment
    end

    # Desfaz a correção do credor, com motivo: volta ao valor do Banco Central; o mês incluído à mão fica "sem valor" (revisão 1, P7).
    def undo(series:, month:, reason:)
      reason = reason.to_s.squish
      raise Refused, I18n.t("indexes.adjust.reason_required") if reason.blank?

      adjustment = IndexAdjustment.find_by!(tenant_id: @tenant.id, series: series.to_s, month: parse_month(month))
      bank = IndexRate.find_by(series: adjustment.series, month: adjustment.month)&.value
      ApplicationRecord.transaction do
        log("correction_undone", adjustment, adjustment.value, bank, reason)
        adjustment.destroy!
      end
      ValuesRecalculationJob.enqueue_for(@tenant, reason: "índice")
      Broadcast.changed
    end

    private
      # Aceita "2026-09" (campo de mês) ou "09/2026". Só meses fechados: o corrente nunca vira mês fechado (R143).
      def parse_month(raw)
        text = raw.to_s.strip
        date = if text.match?(/\A\d{4}-\d{2}(-\d{2})?\z/) then Date.new(text[0, 4].to_i, text[5, 2].to_i, 1)
        elsif text.match?(%r{\A\d{2}/\d{4}\z}) then Date.new(text[3, 4].to_i, text[0, 2].to_i, 1)
        end
        raise Refused, I18n.t("indexes.adjust.month_invalid") unless date
        raise Refused, I18n.t("indexes.adjust.month_open") if date >= Date.current.beginning_of_month
        raise Refused, I18n.t("indexes.adjust.month_invalid") if date < IndexRate::FIRST_MONTH

        date
      rescue Date::Error
        raise Refused, I18n.t("indexes.adjust.month_invalid")
      end

      def parse_value(raw)
        text = raw.to_s.strip
        raise Refused, I18n.t("indexes.adjust.value_invalid") unless text.match?(VALUE_FORMAT)

        BigDecimal(text.tr(",", "."))
      end

      def log(event, adjustment, before, after, reason)
        Change.record!(tenant_id: @tenant.id, user: @user, subject_type: "index_adjustment", subject_id: adjustment.id, event: event, field: adjustment.series,
                       before: [ adjustment.month.strftime("%m/%Y"), before&.to_s("F") ].compact.join(": "), after: after&.to_s("F"), note: reason.truncate(300), origin: "screen")
      end
  end
end
