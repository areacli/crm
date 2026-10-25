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

  test "R174 e critério de aceite: a ficha mostra o atualizado e os componentes de Maria, e a memória de cálculo abre por título" do
    on_the_day do
      entrar(users(:joana))
      get customer_path(@bill.customer)
      assert_response :success
      assert_select "dt", text: "Atualizado"
      assert_select "dd", text: "R$ 1.057,56"
      assert_select "td small", text: /principal corrigido R\$ 1\.005,34 · multa R\$ 20,11 · juros R\$ 32,11 · honorários R\$ 0,00/
      assert_select "summary", text: "Ver memória de cálculo"

      get bill_calculation_memory_path(@bill)
      assert_response :success
      assert_select "caption", text: /Memória de cálculo do título NF-1/
      assert_select "p", text: /Parâmetros de Escola Alfa/
      assert_select "td", text: /IPCA/
      assert_select "dd", text: "R$ 1.057,56"
      assert_select "a", text: "Ver índices"
    end
  end

  test "R179: quem só consulta vê o atualizado e a memória, sem o link de índices nem a edição" do
    on_the_day do
      entrar(users(:carlos))
      get bill_calculation_memory_path(@bill)
      assert_response :success
      assert_select "dd", text: "R$ 1.057,56"
      assert_select "a", text: "Ver índices", count: 0
    end
  end

  test "V10: a memória de cálculo de título de outro credor é recusada e registrada" do
    other = make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    on_the_day do
      entrar(users(:joana))
      assert_difference -> { AccessEvent.where(event: "access_denied", user_id: users(:joana).id).count }, 1 do
        get bill_calculation_memory_path(other)
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

  test "R176, R176a e critério de aceite: o resumo traz um só conjunto de totais com o atualizado somado, as faixas e os segmentos (25/10/2026)" do
    configure_charges(@beta, fine: 0, interest: 2, index: "none")
    make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    recalc_values(@beta)
    on_the_day do
      entrar(users(:ana))
      get root_path
      assert_response :success
      assert_select "h2", text: /Escola Alfa|Clínica Beta/, count: 0
      assert_select "dt", text: "Atualizado", count: 1
      assert_select "h2", text: "Segmentos"
      assert_select "th", text: "Atualizado", minimum: 1
      assert_select "h2", text: /Faixas de atraso/ # Alfa e Beta têm as mesmas faixas: as tabelas somam os dois (25/10/2026)
      assert_select "dd", text: "R$ 2.121,43" # soma dos dois credores
    end
  end

  test "R160 e R177: a aba mostra a regra de cada segmento numa linha, os parâmetros do credor e as cinco políticas" do
    entrar(users(:joana))
    get settings_segments_path
    assert_response :success
    assert_select "td", text: "multa 2% · juros 1% a.m. simples · IPCA · sem honorários"
    assert_select "legend", text: "Parâmetros de encargos do credor"
    %w[Mês\ sem\ índice Forma\ dos\ juros Índice\ negativo Juros\ legais\ antes\ de\ 30/08/2024 Comparação\ dos\ acréscimos\ da\ carga].each { |title| assert_select "legend", text: title }
  end

  test "R163 e critério de aceite: mudar os juros de 1% para 2% mostra o valor antes e depois e a diferença; nada muda até confirmar; confirmado, recalcula" do
    on_the_day do
      entrar(users(:joana))
      patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_interest_pct: "2" } }
      assert_response :success
      assert_select "h1", "Conferir mudança nos segmentos"
      assert_select "h3", text: "Valor atualizado da carteira"
      assert_select "th", text: "Demais"
      assert_select "td", text: "R$ 1.057,56"
      assert_select "td", text: "R$ 1.089,66"
      assert_select "td", text: "R$ 32,10"
      assert_equal 1.0, @alfa.setting.reload.charge_interest_pct.to_f
      assert_equal 105_756, total_of(@bill)
      token = css_select("input[name='confirmation[token]']").first["value"]

      post settings_segment_confirmation_path, params: { tenant_id: @alfa.id, confirmation: { token: token } }
      assert_redirected_to settings_segments_path
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
    token = Segments::Proposal.current(@alfa).with_charges("charge_interest_pct" => "2").token
    Segments::Applier.new(users(:joana)).confirm(@alfa, token)
    perform_enqueued_jobs(only: ValuesRecalculationJob)
    assert_nil total_of(paid)
    assert_nil total_of(withdrawn)
  end

  test "R161: multa acima de 2% num segmento de pessoa física mostra o aviso do CDC na conferência e grava depois dela" do
    entrar(users(:joana))
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "PF", person_type: "person", fine_pct: "10", fees_pct: "0" } }
    assert_response :success
    assert_select "aside", text: /Multa acima de 2% em PF.*CDC, art\. 52, § 1º/
    assert_equal 0, @alfa.segments.where(name: "PF").count
    token = css_select("input[name='confirmation[token]']").first["value"]
    post settings_segment_confirmation_path, params: { tenant_id: @alfa.id, confirmation: { token: token } }
    assert_equal 10, @alfa.segments.find_by!(name: "PF").fine_pct
  end

  test "R160 e R161: honorários sem a marca 'o contrato prevê honorários' são recusados" do
    entrar(users(:joana))
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "Com honorários", fees_pct: "10" } }
    assert_response :unprocessable_content
    assert_select "small[role=alert]", text: "marque se o contrato prevê honorários"
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "Com honorários", fees_pct: "10", fees_in_contract: "1" } }
    assert_response :success
    assert_select "h1", "Conferir mudança nos segmentos"
  end

  test "R162: com a taxa legal, a taxa fixa e a forma dos juros não se aplicam e ficam zeradas ao gravar" do
    segment = Segment.new(tenant: @alfa, name: "Legal", interest_kind: "legal", interest_pct: 3, interest_form: "compound")
    assert segment.valid?
    assert_equal [ nil, "simple" ], [ segment.interest_pct, segment.interest_form ]
  end

  test "R160: percentual inválido volta ao formulário com a mensagem do campo" do
    entrar(users(:joana))
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "X", fine_pct: "dois" } }
    assert_response :unprocessable_content
    assert_select "small[role=alert]", text: /informe o percentual/
  end

  test "R160: o Demais tem regra de encargos e a edita; não tem critérios, e continua sem mover nem desativar" do
    demais = Segment.catch_all_of(@alfa)
    entrar(users(:joana))
    get edit_settings_segment_path(demais)
    assert_response :success
    assert_select "legend", text: "Encargos"
    assert_select "legend", text: "Atraso do contrato (dias)", count: 0
    patch settings_segment_path(demais), params: { tenant_id: @alfa.id, segment: { name: "Qualquer", min_overdue_days: "5", fine_pct: "3", fees_pct: "0", interest_kind: "fixed" } }
    assert_response :success
    token = css_select("input[name='confirmation[token]']").first["value"]
    post settings_segment_confirmation_path, params: { tenant_id: @alfa.id, confirmation: { token: token } }
    demais.reload
    assert_equal [ "Demais", nil, 3 ], [ demais.name, demais.min_overdue_days, demais.fine_pct ]
    post settings_segment_activation_path(demais)
    assert_response :not_found
  end

  test "R179 e MT-3: Marta com a 14 na Alfa e só consulta na Beta muda os encargos da Alfa e é recusada na Beta por envio direto, com registro" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    entrar(marta)
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { charge_interest_pct: "2" } }
    assert_response :success
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
    assert_redirected_to settings_segments_path
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { negative_index_policy: "inventada" } }
    assert_redirected_to settings_segments_path
  end

  test "R180: mudar a política 'Índice negativo' passa pela conferência da base toda" do
    entrar(users(:joana))
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { negative_index_policy: "always" } }
    assert_response :success
    assert_select "li", text: /Índice negativo: Aplica, sem ficar abaixo do original → Aplica sempre/
    assert_select "h3", text: "Valor atualizado da carteira"
    assert_equal "floor", @alfa.setting.reload.negative_index_policy
  end

  test "R182: a política da comparação dos acréscimos passa pela conferência sem mudar valores" do
    entrar(users(:joana))
    patch settings_charges_path, params: { tenant_id: @alfa.id, charges: { surcharge_comparison_policy: "after" } }
    assert_response :success
    assert_select "h3", text: "Valor atualizado da carteira", count: 0
    assert_select "p", text: "Nenhum contrato muda de segmento."
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
