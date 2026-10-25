module Settings
  # Parâmetros de encargos do credor e as cinco políticas (09, R160, R165, R180 a R182): qualquer mudança passa pela conferência do impacto antes
  # de valer (R163). Permissão 14 no credor. Um formulário por cartão; vêm só os campos do cartão.
  class ChargesController < ApplicationController
    include SegmentReview

    PERCENT_FIELDS = %w[charge_fine_pct charge_interest_pct].freeze

    def update
      tenant = tenant_for_change(params[:tenant_id])
      changes = parse(params.expect(charges: TenantSetting::CHARGE_FIELDS.map(&:to_sym)).to_h)
      return redirect_to(settings_segments_path, alert: t("charges.flash.invalid"), status: :see_other) unless changes

      render_review(::Segments::Proposal.current(tenant).with_charges(changes))
    end

    private
      # Percentual digitado (vírgula ou ponto) ou opção da lista; nil se algum campo é inválido.
      def parse(raw)
        raw.each_with_object({}) do |(field, value), parsed|
          if PERCENT_FIELDS.include?(field)
            number = ::Segments::Params.percent(value)
            return nil if number.nil? || number == :invalid || number > 100

            parsed[field] = number.to_s("F")
          else
            return nil unless TenantSetting.defined_enums.fetch(field).key?(value.to_s)

            parsed[field] = value.to_s
          end
        end
      end
  end
end
