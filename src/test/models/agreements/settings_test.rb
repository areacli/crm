require "test_helper"

# Configuração dos acordos (11, R207, R207a, R209, R246): parâmetros com override no segmento, variáveis, limites por perfil e políticas, com registro e sem conferência.
class Agreements::SettingsTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @segment = Segment.catch_all_of(@alfa)
    @segment.update!(**AgreementsTestHelper::EXAMPLE_VARIABLES)
    rebuild_agreement_limits(@alfa)
    @settings = Agreements::Settings.new(users(:joana))
    @operator = profiles(:alfa_operator)
    @manager = profiles(:alfa_manager)
  end

  def history(subject) = Change.where(tenant: @alfa, subject_type: subject).order(:id).pluck(:field, :before, :after)

  test "R207, DA4: um segmento novo nasce com os limites padrão: o gestor acompanha, os outros têm a metade (parcelas para baixo, no mínimo 1)" do
    segment = Segment.create!(tenant: @alfa, name: "Varejo PF", name_key: "varejo pf", agreement_max_installments: 9, agreement_caps: { "installment" => { "fine" => 75, "interest" => 100 }, "cash" => { "fine" => 50 } })

    manager = AgreementLimit.find_by!(segment: segment, profile: @manager)
    operator = AgreementLimit.find_by!(segment: segment, profile: @operator)
    assert_equal [ 9, 75, 100, 50 ], [ manager.max_installments, Agreements::Caps.get(manager.caps, "installment", "fine"), Agreements::Caps.get(manager.caps, "installment", "interest"), Agreements::Caps.get(manager.caps, "cash", "fine") ]
    assert_equal [ 4, 37, 50, 25, 10 ], [ operator.max_installments, Agreements::Caps.get(operator.caps, "installment", "fine"), Agreements::Caps.get(operator.caps, "installment", "interest"), Agreements::Caps.get(operator.caps, "cash", "fine"), operator.min_down_payment_pct ]
    assert_equal 1, AgreementLimit.for(profiles(:beta_operator), Segment.new(agreement_max_installments: 1)).max_installments
  end

  test "R209: um perfil novo nasce com os limites de todos os segmentos do credor" do
    profile = Profile.create!(tenant: @alfa, name: "Supervisão", permissions: %w[view_portfolio negotiate_agreements])

    assert_equal Segment.where(tenant: @alfa).count, AgreementLimit.where(profile: profile).count
    assert_equal 6, AgreementLimit.find_by!(profile: profile, segment: @segment).max_installments
  end

  test "R207a: os parâmetros do credor e o valor próprio do segmento (vazio herda) gravam sem conferência e com registro" do
    @settings.update_parameters(@alfa, { "installment_rate_pct" => "2,5", "installment_method" => "sac", "agreement_days_convention" => "calendar", "agreement_fine_base" => "face" },
                                { @segment.id => { "installment_rate_pct" => "1,5", "installment_method" => "", "agreement_days_convention" => "", "agreement_fine_base" => "" } })

    setting = @alfa.setting.reload
    assert_equal [ BigDecimal("2.5"), "sac", "calendar", "face" ], [ setting.installment_rate_pct, setting.installment_method, setting.agreement_days_convention, setting.agreement_fine_base ]
    installment = Agreements::Parameters.installment(setting, @segment.reload)
    assert_equal [ BigDecimal("1.5"), "sac" ], [ installment.rate_pct, installment.method ], "a taxa é do segmento; o método, do credor"
    assert_includes history("agreement_settings").map(&:first), "installment_method"
    assert_equal [ [ "installment_rate_pct", "", "1.5" ] ], history("agreement_segment")
    assert_equal "calendar", Agreements::Parameters.late_rule(setting, @segment).convention
  end

  test "R207a: parâmetro inválido é recusado com o campo e nada é gravado" do
    error = assert_raises(Agreements::Refused) { @settings.update_parameters(@alfa, { "installment_rate_pct" => "150", "installment_method" => "price", "agreement_days_convention" => "thirty", "agreement_fine_base" => "corrected" }, {}) }
    assert_equal "installment_rate_pct", error.field
    assert_assert_raises_on_blank
  end

  def assert_assert_raises_on_blank
    error = assert_raises(Agreements::Refused) { @settings.update_parameters(@alfa, { "installment_rate_pct" => "", "installment_method" => "price", "agreement_days_convention" => "thirty", "agreement_fine_base" => "corrected" }, {}) }
    assert_equal I18n.t("agreements.settings.invalid_params"), error.message
    assert_equal 0, @alfa.setting.reload.installment_rate_pct
    assert_empty history("agreement_settings")
  end

  test "R207a, DA22: a mora do título de acordo usa multa, juros e índice do segmento e a convenção do acordo (padrão: o boleto, taxa ÷ 30)" do
    configure_charges(@alfa)
    rule = Agreements::Parameters.late_rule(@alfa.setting.reload, @segment.reload)

    assert_equal [ 0.02, 0.01, "thirty", "corrected", "ipca" ], [ rule.fine, rule.rate, rule.convention, rule.fine_base, rule.index ]
  end

  test "R207: as variáveis do segmento gravam com registro de antes e depois" do
    @settings.update_variables(@alfa, { @segment.id => { max_installments: "10", min_installment: "80,00", min_down_payment_pct: "20", down_payment_days: "7", validity_days: "3", tolerance_days: "2", break_days: "45",
                                                       caps: { "installment" => { "fine" => "100", "interest" => "100", "fees" => "50", "principal" => "10" }, "cash" => { "fine" => "100", "interest" => "100", "fees" => "50", "correction" => "30" } } } })

    @segment.reload
    assert_equal [ 10, 8_000, 20, 7, 3, 2, 45 ], [ @segment.agreement_max_installments, @segment.agreement_min_installment_cents, @segment.agreement_min_down_payment_pct, @segment.agreement_down_payment_days,
                                                  @segment.agreement_validity_days, @segment.agreement_tolerance_days, @segment.agreement_break_days ]
    assert_equal 10, Agreements::Caps.get(@segment.agreement_caps, "installment", "principal")
    fields = history("agreement_segment").map(&:first)
    assert_includes fields, "agreement_max_installments"
    assert_includes fields, "agreement_caps"
    assert_equal [ "agreement_max_installments", "12", "10" ], history("agreement_segment").find { |row| row.first == "agreement_max_installments" }
  end

  test "R209: baixar um máximo do segmento baixa os limites dos perfis que passavam dele; subir só acompanha quem altera políticas financeiras" do
    @settings.update_variables(@alfa, { @segment.id => { max_installments: "4", min_installment: "100,00", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30",
                                                       caps: { "installment" => { "fine" => "40", "interest" => "100", "fees" => "50" }, "cash" => { "fine" => "100", "interest" => "100", "fees" => "50", "correction" => "30" } } } })

    operator = AgreementLimit.find_by!(segment: @segment, profile: @operator)
    manager = AgreementLimit.find_by!(segment: @segment, profile: @manager)
    assert_equal [ 4, 40 ], [ operator.max_installments, Agreements::Caps.get(operator.caps, "installment", "fine") ], "o limite do Operador (6 parcelas, 50%) baixou para o do segmento"
    assert_equal [ 4, 40 ], [ manager.max_installments, Agreements::Caps.get(manager.caps, "installment", "fine") ]
    assert_equal 25, Agreements::Caps.get(operator.caps, "installment", "fees"), "o que não passava do teto não muda"
    assert_includes history("agreement_limit").map(&:first), "profile:#{operator.profile_id}"

    @settings.update_variables(@alfa, { @segment.id => { max_installments: "20", min_installment: "100,00", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30",
                                                       caps: { "installment" => { "fine" => "90", "interest" => "100", "fees" => "50" }, "cash" => { "fine" => "100", "interest" => "100", "fees" => "50", "correction" => "30" } } } })
    assert_equal [ 4, 40 ], [ operator.reload.max_installments, Agreements::Caps.get(operator.caps, "installment", "fine") ], "o Operador não sobe sozinho"
    assert_equal [ 20, 90 ], [ manager.reload.max_installments, Agreements::Caps.get(manager.caps, "installment", "fine") ], "o Gestor acompanha o segmento"
  end

  test "R209: subir a entrada mínima do segmento sobe as dos perfis que ficavam abaixo" do
    @settings.update_variables(@alfa, { @segment.id => { max_installments: "12", min_installment: "100,00", min_down_payment_pct: "30", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30" } })

    assert_equal [ 30, 30 ], AgreementLimit.where(segment: @segment).order(:profile_id).pluck(:min_down_payment_pct)
  end

  test "R207: variável inválida é recusada" do
    assert_raises(Agreements::Refused) do
      @settings.update_variables(@alfa, { @segment.id => { max_installments: "0", min_installment: "100,00", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30" } })
    end
    assert_raises(Agreements::Refused) do
      @settings.update_variables(@alfa, { @segment.id => { max_installments: "12", min_installment: "abc", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30" } })
    end
    assert_raises(Agreements::Refused) do
      @settings.update_variables(@alfa, { @segment.id => { max_installments: "12", min_installment: "100,00", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30", caps: { "installment" => { "fine" => "101" } } } })
    end
    assert_equal 12, @segment.reload.agreement_max_installments
  end

  test "R209, N23: o limite do perfil fica dentro das variáveis do segmento e aceita os tetos em reais opcionais" do
    @settings.update_limits(@alfa, { @segment.id => { @operator.id => { max_installments: "5", min_down_payment_pct: "15", ceiling_discount: "50,00", ceiling_value: "2.000,00",
                                                                      caps: { "installment" => { "fine" => "30" } } } } })

    limit = AgreementLimit.find_by!(segment: @segment, profile: @operator)
    assert_equal [ 5, 15, 5_000, 200_000, 30, 50 ], [ limit.max_installments, limit.min_down_payment_pct, limit.ceiling_discount_cents, limit.ceiling_value_cents,
                                                      Agreements::Caps.get(limit.caps, "installment", "fine"), Agreements::Caps.get(limit.caps, "installment", "interest") ]
    assert_equal 1, history("agreement_limit").size

    above = assert_raises(Agreements::Refused) { @settings.update_limits(@alfa, { @segment.id => { @operator.id => { max_installments: "13", min_down_payment_pct: "15" } } }) }
    assert_equal I18n.t("agreements.settings.limit_above_segment", name: "Operador em Demais"), above.message
    below = assert_raises(Agreements::Refused) { @settings.update_limits(@alfa, { @segment.id => { @operator.id => { max_installments: "5", min_down_payment_pct: "5" } } }) }
    assert_includes below.message, "Operador em Demais"
    over_cap = assert_raises(Agreements::Refused) { @settings.update_limits(@alfa, { @segment.id => { @operator.id => { max_installments: "5", min_down_payment_pct: "15", caps: { "installment" => { "fees" => "60" } } } } }) }
    assert_includes over_cap.message, "Operador em Demais"
    assert_equal 5, limit.reload.max_installments
  end

  test "R246: as políticas gravam com registro de antes e depois, só o que mudou, e o resto vale o padrão" do
    @settings.update_policies(@alfa, { "break_form" => "single_title", "late_charges" => "by_parameters", "tolerance_agreement" => { kind: "cents", value: "2,50" },
                                       "minimum_to_break" => { kind: "percent", value: "1,5" } })

    values = Agreements::Policies.for(@alfa.setting.reload)
    assert_equal "single_title", values["break_form"]
    assert_equal "payment", values["effectuation"], "padrão"
    assert_equal({ "kind" => "cents", "value" => 250 }, values["tolerance_agreement"])
    assert_equal({ "kind" => "percent", "value" => 150 }, values["minimum_to_break"])
    assert_equal %w[break_form minimum_to_break tolerance_agreement], history("agreement_settings").map(&:first).sort
    assert_equal [ "R$ 1,00", "R$ 2,50" ], history("agreement_settings").find { |row| row.first == "tolerance_agreement" }.drop(1)
    assert_equal [ "R$ 0,00", "1,50%" ], history("agreement_settings").find { |row| row.first == "minimum_to_break" }.drop(1)
  end

  test "R246: política com opção que não existe ou valor inválido é recusada e nada é gravado" do
    assert_raises(Agreements::Refused) { @settings.update_policies(@alfa, { "break_form" => "quebrar_tudo" }) }
    assert_raises(Agreements::Refused) { @settings.update_policies(@alfa, { "tolerance_direct" => { kind: "percent", value: "120" } }) }
    assert_raises(Agreements::Refused) { @settings.update_policies(@alfa, { "tolerance_direct" => { kind: "cents", value: "abc" } }) }
    assert_equal({}, @alfa.setting.reload.agreement_policies)
  end

  test "R229: o mínimo para quebrar pode ser igual à tolerância de valor dos títulos de acordo" do
    @settings.update_policies(@alfa, { "minimum_to_break" => { kind: "tolerance", value: "" } })

    assert_equal "tolerance", Agreements::Policies.value(@alfa.setting.reload, "minimum_to_break")["kind"]
  end

  test "R210: o esquema das políticas tem padrão, opções e o que congela; as de crédito e pagamento ficam na aba de pagamentos" do
    assert_equal 33, Agreements::Policies::SCHEMA.size
    assert_equal({ "kind" => "cents", "value" => 100 }, Agreements::Policies.value(@alfa.setting, "tolerance_agreement"), "padrão R$ 1,00")
    assert_equal({ "kind" => "cents", "value" => 0 }, Agreements::Policies.value(@alfa.setting, "tolerance_promise"))
    assert_includes Agreements::Policies.keys(:payments), "credit_use"
    assert_includes Agreements::Policies.keys(:payments), "tolerance_direct"
    assert_not_includes Agreements::Policies.frozen_for(@alfa.setting).keys, "credit_use"
    assert_includes Agreements::Policies.frozen_for(@alfa.setting).keys, "credit_across_contracts"
    assert_equal 0, Agreements::Policies.tolerance_cents(@alfa.setting, "direct", 50_000)
    assert_equal 100, Agreements::Policies.tolerance_cents(@alfa.setting, "agreement", 50_000)
  end
end
