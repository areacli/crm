module Agreements
  # Configuração dos acordos de um credor (11, R207, R207a, R209, R246; permissão 14): parâmetros de encargos do acordo com override no segmento, variáveis do
  # segmento, limites por perfil e políticas. Cada mudança fica registrada com quem, quando, antes e depois (PD4) e vale só para as propostas novas (R210).
  # Nenhuma delas muda título nem segmento de ninguém: gravam sem conferência do impacto (R207).
  class Settings
    SUBJECT = "agreement_settings"

    def initialize(actor) = @actor = actor

    # Parâmetros do credor (`values`: installment_rate_pct, installment_method, agreement_days_convention, agreement_fine_base) e o override de cada segmento
    # (`overrides`: { id do segmento => mesmos campos, vazio herda }).
    def update_parameters(tenant, values, overrides)
      ApplicationRecord.transaction do
        setting = tenant.setting
        setting.assign_attributes(parse_params(values, required: true))
        log_changes(tenant, setting, SUBJECT, tenant.id)
        setting.save!
        Segment.where(tenant_id: tenant.id, id: overrides.keys).find_each do |segment|
          segment.assign_attributes(parse_params(overrides.fetch(segment.id), required: false))
          log_changes(tenant, segment, "agreement_segment", segment.id)
          segment.save!
        end
      end
    end

    # Políticas do credor: `values` é { chave => opção } e, nas de valor, { chave => { kind:, value: } }.
    def update_policies(tenant, values)
      setting = tenant.setting
      stored = (setting.agreement_policies || {}).dup
      values.each do |key, raw|
        entry = Policies.entry(key)
        stored[entry.key] = entry.kind == :choice ? raw.to_s : parse_amount(entry, raw)
        raise Refused.new(I18n.t("agreements.settings.invalid_policy", name: I18n.t("agreements.policies.#{entry.key}.title")), field: entry.key) unless Policies.valid?(entry, stored[entry.key])
      end
      ApplicationRecord.transaction do
        Policies.keys.each do |key|
          before = Policies.value(setting, key)
          after = Policies.valid?(Policies.entry(key), stored[key]) ? stored[key] : Policies.entry(key).default
          next if before == after

          Change.record!(tenant: tenant, user: @actor, subject_type: SUBJECT, subject_id: tenant.id, event: "#{key}_changed", field: key, before: describe(before), after: describe(after))
        end
        setting.update!(agreement_policies: stored.slice(*Policies.keys))
      end
      setting
    end

    # Variáveis de acordo dos segmentos do credor (R207): `segments` é { id do segmento => { max_installments:, ..., caps: { "installment" => {...}, "cash" => {...} } } }.
    # Baixar um máximo baixa os limites dos perfis que passavam dele; subir a entrada mínima sobe as dos perfis que ficavam abaixo; quem altera políticas
    # financeiras acompanha o segmento também quando um máximo sobe (R209). Tudo com registro.
    def update_variables(tenant, segments)
      ApplicationRecord.transaction do
        Segment.where(tenant_id: tenant.id, id: segments.keys).find_each do |segment|
          values = segments.fetch(segment.id)
          before_caps = Caps.normalize(segment.agreement_caps)
          segment.assign_attributes(agreement_max_installments: int(values[:max_installments]), agreement_min_installment_cents: cents(values[:min_installment]),
                                    agreement_min_down_payment_pct: int(values[:min_down_payment_pct]), agreement_down_payment_days: int(values[:down_payment_days]),
                                    agreement_validity_days: int(values[:validity_days]), agreement_tolerance_days: int(values[:tolerance_days]), agreement_break_days: int(values[:break_days]),
                                    agreement_caps: parse_caps(values[:caps], before_caps))
          raise Refused.new(I18n.t("agreements.settings.invalid_variables", segment: segment.name)) unless segment.valid?

          log_changes(tenant, segment, "agreement_segment", segment.id, extra: { agreement_caps: before_caps })
          follow_limits(segment, before_caps)
          segment.save!
        end
      end
    end

    # Limites dos perfis (R209, N23): `limits` é { id do segmento => { id do perfil => { max_installments:, min_down_payment_pct:, ceiling_discount:, ceiling_value:, caps: } } }.
    def update_limits(tenant, limits)
      ApplicationRecord.transaction do
        Segment.where(tenant_id: tenant.id, id: limits.keys).find_each do |segment|
          Profile.where(tenant_id: tenant.id, id: limits.fetch(segment.id).keys).find_each do |profile|
            values = limits.fetch(segment.id).fetch(profile.id)
            limit = AgreementLimit.for(profile, segment)
            before = describe_limit(limit)
            limit.assign_attributes(max_installments: int(values[:max_installments]), min_down_payment_pct: int(values[:min_down_payment_pct]),
                                    ceiling_discount_cents: optional_cents(values[:ceiling_discount]), ceiling_value_cents: optional_cents(values[:ceiling_value]),
                                    caps: parse_caps(values[:caps], limit.caps))
            check_within_segment!(limit, segment, profile)
            next if describe_limit(limit) == before && limit.persisted?

            Change.record!(tenant: tenant, user: @actor, subject_type: "agreement_limit", subject_id: segment.id, event: "limit_changed", field: "profile:#{profile.id}", before: before, after: describe_limit(limit))
            limit.save!
          end
        end
      end
    end

    private
      PARAM_FIELDS = %w[installment_rate_pct installment_method agreement_days_convention agreement_fine_base].freeze

      # Percentual com vírgula ou ponto; método e opções da lista. `required`: no credor o campo não pode ficar vazio; no segmento, vazio herda.
      def parse_params(values, required:)
        PARAM_FIELDS.to_h do |field|
          raw = values[field].to_s.strip
          if raw.empty?
            raise Refused.new(I18n.t("agreements.settings.invalid_params"), field: field) if required

            [ field, nil ]
          elsif field == "installment_rate_pct"
            number = Segments::Params.percent(raw)
            raise Refused.new(I18n.t("agreements.settings.invalid_params"), field: field) if number.nil? || number == :invalid || number > 100

            [ field, number ]
          else
            raise Refused.new(I18n.t("agreements.settings.invalid_params"), field: field) unless valid_option?(field, raw)

            [ field, raw ]
          end
        end
      end

      def valid_option?(field, raw)
        { "installment_method" => Segment::INSTALLMENT_METHODS, "agreement_days_convention" => Segment::DAYS_CONVENTIONS, "agreement_fine_base" => Segment::FINE_BASES }.fetch(field).include?(raw)
      end

      def log_changes(tenant, record, subject_type, subject_id, extra: {})
        record.changes.slice(*PARAM_FIELDS, *Segment::AGREEMENT_VARIABLE_FIELDS.map(&:to_s)).each do |field, (before, after)|
          Change.record!(tenant: tenant, user: @actor, subject_type: subject_type, subject_id: subject_id, event: "#{field}_changed", field: field, before: before.to_s, after: after.to_s)
        end
        if extra.key?(:agreement_caps) && Caps.normalize(record.agreement_caps) != extra[:agreement_caps]
          Change.record!(tenant: tenant, user: @actor, subject_type: subject_type, subject_id: subject_id, event: "agreement_caps_changed", field: "agreement_caps",
                         before: describe_caps(extra[:agreement_caps]), after: describe_caps(Caps.normalize(record.agreement_caps)))
        end
      end

      # R209: o que muda nos limites quando o segmento muda.
      def follow_limits(segment, before_caps)
        AgreementLimit.where(segment_id: segment.id).includes(:profile).find_each do |limit|
          follows = limit.profile.permitted?("change_financial_policies")
          caps = Caps.normalize(limit.caps)
          new_caps = Caps.clamp(caps, segment.agreement_caps)
          Caps::KINDS.each { |kind| Caps::COMPONENTS.each { |component| new_caps[kind][component] = Caps.get(segment.agreement_caps, kind, component) if follows && Caps.get(segment.agreement_caps, kind, component) > Caps.get(before_caps, kind, component) } }
          installments = limit.max_installments
          installments = [ installments, segment.agreement_max_installments ].min
          installments = segment.agreement_max_installments if follows && segment.agreement_max_installments > segment.agreement_max_installments_was
          down = [ limit.min_down_payment_pct, segment.agreement_min_down_payment_pct ].max
          next if new_caps == caps && installments == limit.max_installments && down == limit.min_down_payment_pct

          before = describe_limit(limit)
          limit.assign_attributes(caps: new_caps, max_installments: installments, min_down_payment_pct: down)
          Change.record!(tenant_id: segment.tenant_id, user: @actor, subject_type: "agreement_limit", subject_id: segment.id, event: "limit_followed", field: "profile:#{limit.profile_id}", before: before, after: describe_limit(limit))
          limit.save!
        end
      end

      # Um limite nunca passa das variáveis do segmento (R209): desconto até o teto, parcelas até o máximo e entrada de, no mínimo, a do segmento.
      def check_within_segment!(limit, segment, profile)
        name = "#{profile.name} em #{segment.name}"
        raise Refused.new(I18n.t("agreements.settings.invalid_limit", name: name)) unless limit.valid?
        raise Refused.new(I18n.t("agreements.settings.limit_above_segment", name: name)) if limit.max_installments > segment.agreement_max_installments ||
                                                                                          limit.min_down_payment_pct < segment.agreement_min_down_payment_pct ||
                                                                                          Caps::KINDS.any? { |kind| Caps::COMPONENTS.any? { |component| Caps.get(limit.caps, kind, component) > Caps.get(segment.agreement_caps, kind, component) } }
      end

      def parse_caps(raw, fallback)
        return Caps.normalize(fallback) if raw.nil?

        Caps::KINDS.to_h do |kind|
          [ kind, Caps::COMPONENTS.to_h do |component|
            value = raw.dig(kind, component) if raw.respond_to?(:dig)
            [ component, value.nil? ? Caps.get(fallback, kind, component) : int(value, max: 100) ]
          end ]
        end
      end

      def int(raw, max: nil)
        number = Integer(raw.to_s.strip, exception: false)
        raise Refused.new(I18n.t("agreements.settings.invalid_number")) if number.nil? || number.negative? || (max && number > max)

        number
      end

      def cents(raw)
        value = raw.to_s.strip
        return 0 if value.match?(/\A0([.,]0{1,2})?\z/)

        parsed, problem = Money.parse_cents(value)
        raise Refused.new(I18n.t("agreements.settings.invalid_money", problem: problem)) unless parsed

        parsed
      end

      def optional_cents(raw) = raw.to_s.strip.empty? ? nil : cents(raw)

      # Valor de uma política de valor: em reais (centavos) ou em percentual (centésimos de ponto: 1,5% é 150).
      def parse_amount(entry, raw)
        kind = raw[:kind].to_s
        raise Refused.new(I18n.t("agreements.settings.invalid_policy", name: I18n.t("agreements.policies.#{entry.key}.title")), field: entry.key) unless entry.options.include?(kind)
        return { "kind" => kind, "value" => 0 } if kind == "tolerance"

        if kind == "percent"
          number = Segments::Params.percent(raw[:value].to_s.presence || "0")
          raise Refused.new(I18n.t("agreements.settings.invalid_policy", name: I18n.t("agreements.policies.#{entry.key}.title")), field: entry.key) if number.nil? || number == :invalid || number > 100

          { "kind" => kind, "value" => (number * 100).round.to_i }
        else
          { "kind" => kind, "value" => cents(raw[:value]) }
        end
      end

      def describe(value)
        return value.to_s unless value.is_a?(Hash)

        case value["kind"]
        when "percent" then "#{format('%.2f', value['value'] / 100.0).tr('.', ',')}%"
        when "tolerance" then I18n.t("agreements.policies.minimum_to_break.options.tolerance")
        else "R$ #{Money.format(value['value'])}"
        end
      end

      def describe_caps(caps)
        Caps::KINDS.map { |kind| "#{I18n.t("agreements.modes.#{kind}")}: " + Caps::COMPONENTS.map { |component| "#{I18n.t("agreements.components.#{component}")} #{Caps.get(caps, kind, component)}%" }.join(", ") }.join(" · ")
      end

      def describe_limit(limit)
        "#{describe_caps(limit.caps)} · até #{limit.max_installments} parcelas · entrada #{limit.min_down_payment_pct}%" \
          "#{" · teto do desconto R$ #{Money.format(limit.ceiling_discount_cents)}" if limit.ceiling_discount_cents}#{" · teto do valor R$ #{Money.format(limit.ceiling_value_cents)}" if limit.ceiling_value_cents}"
      end
  end
end
