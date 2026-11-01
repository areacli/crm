require "test_helper"

# Telas e fluxos dos encargos (09): ficha com componentes e memória de cálculo, coluna da lista, cartão por credor no resumo, regra do segmento,
# conferência do impacto, aviso do CDC, permissões (R179, MT-3), comparação dos acréscimos da carga (R178, R182) e isolamento por credor (V10).
class ChargesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    seed_indexes!
    configure_charges(@alfa)
    @bill = make_bill(@alfa, due: DUE)
    recalc(@alfa)
    recalc_values(@alfa)
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  def on_the_day(&block) = travel_to(TODAY.in_time_zone.change(hour: 10), &block)

  test "R174 e critério de aceite: a ficha mostra o atualizado e os componentes de Maria, e a memória de cálculo fica na página do título (revisão 7)" do
    on_the_day do
      entrar(users(:joana))
      get customer_path(@bill.customer)
      assert_response :success
      assert_select "dt", text: "Atualizado"
      assert_select "dd", text: "R$ 1.057,56"
            assert_select "dl.composicao", 0 # padrões de interface, revisão 27: os componentes ficam na página do título
      assert_select "summary", text: "Ver memória de cálculo", count: 0

      get bill_path(@bill)
      assert_response :success
      assert_select "dl.composicao", text: /Principal corrigido\s*R\$ 1\.005,34\s*Multa\s*R\$ 20,11\s*Juros\s*R\$ 32,11\s*Honorários\s*R\$ 0,00\s*Atualizado\s*R\$ 1\.057,56/
      assert_select "h2", text: "Memória de cálculo"
      assert_select "caption", text: /Memória de cálculo do título NF-1/
      assert_select "caption small", text: /pelos parâmetros de Escola Alfa/
      assert_select "td", text: /IPCA/
      assert_select "a", text: "Ver índices"
    end
  end

  test "R179: quem só consulta vê o atualizado e a memória, sem o link de índices nem a edição" do
    on_the_day do
      entrar(users(:carlos))
      get bill_path(@bill)
      assert_response :success
      assert_select "caption", text: /Memória de cálculo do título NF-1/
      assert_select "a", text: "Ver índices", count: 0
    end
  end

  test "V10: a memória de cálculo de título de outro credor é recusada e registrada" do
    other = make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    on_the_day do
      entrar(users(:joana))
      assert_difference -> { AccessEvent.where(event: "access_denied", user_id: users(:joana).id).count }, 1 do
        get bill_path(other)
        assert_response :not_found
      end
    end
  end

  test "R175: a lista de clientes tem a coluna Atualizado ao lado de Vencido, sem total" do
    on_the_day do
      entrar(users(:joana))
      get customers_path
      assert_select "th", text: "Atualizado"
      assert_select "td", text: "R$ 1.057,56"
      assert_select "tfoot", count: 0
    end
  end

  test "R176, R176a e critério de aceite: o resumo traz um só conjunto de totais com o atualizado somado e as faixas, sem segmentos (13, SG10)" do
    configure_charges(@beta, fine: 0, interest: 2, index: "none")
    make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    recalc_values(@beta)
    on_the_day do
      entrar(users(:ana))
      get root_path
      assert_response :success
      assert_select "h2", text: /Escola Alfa|Clínica Beta/, count: 0
      assert_select "dt", text: /\AAtualizado/, count: 1
      assert_select "h2", text: "Segmentos", count: 0
      assert_select "th", text: "Atualizado", minimum: 1
      assert_select "h2", text: /Faixas de atraso/ # Alfa e Beta têm as mesmas faixas: as tabelas somam os dois (25/10/2026)
      assert_select "dd", text: /R\$ 2.121,43/ # soma dos dois credores
    end
  end

  test "R160 e R292: o enquadramento financeiro mostra as regras de cada item numa linha, os parâmetros do credor e as cinco políticas" do
    entrar(users(:joana))
    get settings_tiers_path
    assert_response :success
    assert_select "tr.detalhe-da-linha p", text: "Encargos: multa 2% · juros 1% a.m. simples · IPCA · sem honorários."
    assert_select "legend", text: "Parâmetros de encargos do credor"
    %w[Mês\ sem\ índice Forma\ dos\ juros Índice\ negativo Juros\ legais\ antes\ de\ 30/08/2024 Comparação\ dos\ acréscimos\ da\ carga].each { |title| assert_select "legend", text: title }
  end

  test "R163 e critério de aceite: mudar os juros de 1% para 2% mostra o valor antes e depois e a diferença; nada muda até confirmar; confirmado, recalcula" do
    on_the_day do
      entrar(users(:joana))
      patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_interest_pct: "2" } }
      follow_review
      assert_select "h1", "Conferir o impacto"
      assert_select "h2", text: "Valor atualizado"
      assert_select "th", text: "Demais"
      assert_select "td", text: "R$ 1.057,56"
      assert_select "td", text: "R$ 1.089,66"
      assert_select "td", text: "R$ 32,10"
      assert_equal 1.0, @alfa.setting.reload.charge_interest_pct.to_f
      assert_equal 105_756, total_of(@bill)
      confirm_review(@alfa)
      assert_redirected_to settings_tiers_path
      assert_equal 2.0, @alfa.setting.reload.charge_interest_pct.to_f
      perform_enqueued_jobs(only: ValuesRecalculationJob)
      assert_equal 108_966, total_of(@bill)
      log = Change.where(subject_type: "tenant_setting", field: "charge_interest_pct").sole
      assert_equal [ "1.0", "2.0", users(:joana), @alfa.id ], [ log.before, log.after, log.user, log.tenant_id ]
    end
  end

  test "R163: título pago ou retirado não muda de valor com a regra nova (cenários fechados)" do
    paid = make_bill(@alfa, number: "PAGO", due: DUE, status: :paid)
    withdrawn = make_bill(@alfa, number: "RET", due: DUE, status: :withdrawn)
    token = Tiers::Proposal.current(@alfa).with_charges("charge_interest_pct" => "2").token
    Tiers::Applier.new(users(:joana)).confirm(@alfa, token)
    perform_enqueued_jobs(only: ValuesRecalculationJob)
    assert_nil total_of(paid)
    assert_nil total_of(withdrawn)
  end

  test "R161: multa acima de 2% num item que pode pegar pessoa física mostra o aviso do CDC na conferência e grava depois dela" do
    tier = make_tier(@alfa, "PF", person_type: "person")
    entrar(users(:joana))
    patch settings_tier_path(tier), params: { tier: { fine_pct: "10", fees_pct: "0", interest_kind: "none", promise_max_days: "30" } }
    follow_review
    assert_select "p", text: /Multa acima de 2% em PF.*CDC, art\. 52, § 1º/
    assert_nil tier.reload.fine_pct
    confirm_review(@alfa)
    assert_equal 10, tier.reload.fine_pct
  end

  test "R160 e R161: honorários sem a marca 'o contrato prevê honorários' são recusados" do
    tier = make_tier(@alfa, "Com honorários")
    entrar(users(:joana))
    patch settings_tier_path(tier), params: { tier: { fees_pct: "10", promise_max_days: "30" } }
    assert_response :unprocessable_content
    assert_select "small[role=alert]", text: "marque se o contrato prevê honorários"
    patch settings_tier_path(tier), params: { tier: { fees_pct: "10", fees_in_contract: "1", promise_max_days: "30" } }
    follow_review
    assert_select "h1", "Conferir o impacto"
  end

  test "R162: com a taxa legal, a taxa fixa e a forma dos juros não se aplicam e ficam zeradas ao gravar" do
    tier = Tier.new(tenant: @alfa, kind: "financial", catch_all: true, interest_kind: "legal", interest_pct: 3, interest_form: "compound")
    assert tier.valid?
    assert_equal [ nil, "simple" ], [ tier.interest_pct, tier.interest_form ]
  end

  test "R160: percentual inválido volta ao formulário com a mensagem do campo" do
    tier = make_tier(@alfa, "X")
    entrar(users(:joana))
    patch settings_tier_path(tier), params: { tier: { fine_pct: "dois", promise_max_days: "30" } }
    assert_response :unprocessable_content
    assert_select "small[role=alert]", text: /informe o percentual/
  end

  test "R160, R265: o Demais tem regras e as edita pela conferência; não sai do enquadramento" do
    demais = Tier.catch_all_of(@alfa)
    entrar(users(:joana))
    get edit_settings_tier_path(demais)
    assert_response :success
    assert_select "legend", text: "Encargos"
    patch settings_tier_path(demais), params: { tier: { fine_pct: "3", fees_pct: "0", interest_kind: "fixed", promise_max_days: "30" } }
    follow_review
    confirm_review(@alfa)
    assert_equal [ "Demais", 3 ], [ demais.reload.name, demais.fine_pct ]
    delete settings_tier_path(demais)
    assert_response :not_found
  end

  test "R179 e MT-3: Marta com a 14 na Alfa e só consulta na Beta muda os encargos da Alfa e é recusada na Beta por envio direto, com registro" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    entrar(marta)
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_interest_pct: "2" } }
    assert_response :see_other
    assert_difference -> { AccessEvent.where(event: "access_denied", tenant_id: @beta.id, user_id: marta.id).count }, 1 do
      patch settings_charges_path, params: { tenant_id: @beta.id, charges: { charge_interest_pct: "2" } }
      assert_response :not_found
    end
    assert_equal 0, @beta.setting.reload.charge_interest_pct.to_f
  end

  test "R179: sem a 14 o envio direto dos encargos é recusado" do
    reader = make_user(@alfa, %w[change_settings])
    entrar(reader)
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_interest_pct: "2" } }
    assert_response :not_found
  end

  test "valores inválidos nos parâmetros voltam à aba com o aviso, sem conferência" do
    entrar(users(:joana))
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_fine_pct: "250" } }
    assert_redirected_to settings_tiers_path
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { negative_index_policy: "inventada" } }
    assert_redirected_to settings_tiers_path
  end

  test "R180: mudar a política 'Índice negativo' passa pela conferência da base toda" do
    entrar(users(:joana))
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { negative_index_policy: "always" } }
    follow_review
    assert_select "h3", text: /Encargos do credor/
    assert_select "h2", text: "Valor atualizado"
    assert_equal "floor", @alfa.setting.reload.negative_index_policy
  end

  test "R182: a política da comparação dos acréscimos passa pela conferência sem mudar valores" do
    entrar(users(:joana))
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { surcharge_comparison_policy: "after" } }
    follow_review
    assert_select "h2", text: "Valor atualizado", count: 0
    assert_select "strong", text: "Nenhum contrato muda de item."
  end

  test "R178 e R182 (antes de confirmar): a conferência da carga mostra multa informada, calculada e a diferença" do
    on_the_day do
      header = CsvHelper::HEADER + %w[multa_credor]
      checked = run_portfolio_import([ csv_line("documento" => PaymentsHelper::JOAO, "nome" => "João", "contrato" => "CT-9", "titulo" => "NF-9", "vencimento" => "15/07/2026", "valor" => "1.000,00", "multa_credor" => "20,00") ], header: header)
      entrar(users(:joana))
      get import_path(checked)
      assert_select "h2", text: "Acréscimos informados e calculados pelo CRM"
      assert_select "tr", text: /Multa\s*R\$ 20,00\s*R\$ 20,11/
    end
  end

  test "R182 (depois de confirmar): a conferência mostra só os acréscimos informados; a comparação vem depois do recálculo, com o segmento exato" do
    @alfa.setting.update!(surcharge_comparison_policy: "after")
    on_the_day do
      header = CsvHelper::HEADER + %w[multa_credor]
      checked = run_portfolio_import([ csv_line("documento" => PaymentsHelper::JOAO, "nome" => "João", "contrato" => "CT-9", "titulo" => "NF-9", "vencimento" => "15/07/2026", "valor" => "1.000,00", "multa_credor" => "20,00") ], header: header)
      assert_nil checked.summary_data[:surcharge_comparison]
      Portfolio::ImportService.new.confirm(checked, by: users(:joana))
      3.times { perform_enqueued_jobs(only: [ ConfirmImportJob, SegmentsRecalculationJob, ValuesRecalculationJob ]) } # cada um enfileira o seguinte
      checked.reload
      comparison = checked.summary_data[:surcharge_comparison]
      assert_equal "after", comparison[:moment]
      fine = comparison[:totals].find { |total| total[:name] == "fine" }
      assert_equal [ 2000, 2011 ], [ fine[:informed], fine[:calculated] ]
    end
  end

  test "R173: confirmar uma carga de carteira recalcula os segmentos e, depois, os valores; pagamentos e estornos recalculam os valores" do
    make_channel(@alfa)
    on_the_day do
      run_payments_import([ payment_line("titulo" => "NF-1", "valor" => "100,00", "data_pagamento" => "21/10/2026") ], confirm: true)
      assert_enqueued_with(job: ValuesRecalculationJob)
    end
  end
end
