module Portfolio
  # Histórico de um título (05, R100): as versões do valor, os pagamentos aplicados, os estornos e as divergências, em ordem de data. A
  # alocação e o estorno saem dos próprios pagamentos e estornos (o principal é o único componente com valor); nada é gravado duas vezes.
  class BillHistory
    Event = Data.define(:date, :at, :kind, :cents, :text)

    attr_reader :bill

    def initialize(bill) = @bill = bill

    def versions = @versions ||= bill.value_versions.includes(:import, :user).in_order.to_a

    def discrepancies = @discrepancies ||= bill.value_discrepancies.includes(:handled_by).order(:id).to_a

    # Linha do tempo, da mais antiga à mais recente: data do fato, depois a hora do registro.
    def events
      @events ||= (version_events + payment_events + reversal_events + discrepancy_events).sort_by { |event| [ event.date, event.at ] }
    end

    private
      def version_events
        versions.each_with_index.map do |version, index|
          who = version.user&.name
          text = index.zero? ? "Valor inicial" : "Valor alterado"
          text += " (importação de #{version.import.created_at.in_time_zone.strftime('%d/%m/%Y')}#{", confirmada por #{who}" if who})" if version.import
          Event.new(version.created_at.to_date, version.created_at, :version, version.amount_cents, text)
        end
      end

      def payment_events
        bill.payments.applied.includes(:channel).order(:paid_on, :id).map do |payment|
          Event.new(payment.paid_on, payment.created_at, :payment, payment.applied_cents, "Pagamento #{payment.identifier} (#{payment.channel.description}) aplicado ao título")
        end
      end

      def reversal_events
        PaymentReversal.joins(:payment).where(payments: { bill_id: bill.id }).where("payment_reversals.from_bill_cents > 0").includes(:payment).order(:reversed_on, :id).map do |reversal|
          Event.new(reversal.reversed_on, reversal.created_at, :reversal, -reversal.from_bill_cents, "Estorno #{reversal.identifier} do pagamento #{reversal.payment.identifier}")
        end
      end

      def discrepancy_events
        discrepancies.flat_map do |item|
          events = [ Event.new(item.created_at.to_date, item.created_at, :discrepancy, item.reported_cents, "Divergência: o credor informou outro valor (#{I18n.t("discrepancies.effects.#{item.effect}")})") ]
          if item.handled?
            events << Event.new(item.handled_at.to_date, item.handled_at, :handled, nil, "Divergência tratada por #{item.handled_by&.name || 'usuário removido'}: #{I18n.t("discrepancies.choices.#{item.choice}").downcase}")
          end
          events
        end
      end
  end
end
