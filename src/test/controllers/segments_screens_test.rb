require "test_helper"

# Telas dos segmentos e do enquadramento financeiro (13, R252 a R298): lista, editor em blocos (rascunho, operações, "Conferir" em segundo plano),
# criar sem uso, mudar segmento usado pela conferência, apagar e desativar, glossário, enquadramento (incluir, mover, tirar, regras), lista de
# clientes com o filtro por segmento e a coluna "Enquadramento", ficha, permissões e isolamento por credor (V10).
class SegmentsScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  def text(*lines) = lines.join("\n")

  test "R295: a lista mostra nome, o que seleciona, o texto curto, onde é usado e a situação; sem segmento, o estado vazio" do
    entrar(users(:joana))
    get settings_segments_path
    assert_select "p.vazio", text: /Nenhum segmento criado/
    make_tier(@alfa, "Longo", min_overdue_days: 90)
    make_segment(@alfa, "PF sem uso", subject: "customers", person_type: "person")
    get settings_segments_path
    assert_select "th a", text: "Longo"
    assert_select "td code", text: "atraso >= 90"
    assert_select "td", text: "Enquadramento financeiro, item 1"
    assert_select "td", text: "Sem uso"
    assert_select "td", text: "Clientes"
  end

  test "R252, R253: criar um segmento sem uso grava na hora, não muda o enquadramento e registra o texto" do
    contract = make_contract(@alfa, "C1", bills: [ { overdue: 120 } ])
    recalc(@alfa)
    entrar(users(:joana))
    get new_settings_segment_path(tenant_id: @alfa.id)
    assert_select "h2", text: "Nome"
    assert_select "textarea[name='segment[source]']", text: /contratos/
    assert_select "h2", text: "Como fica"
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "Atraso longo", source: text("Contratos", "  atraso > 90") } }
    assert_redirected_to settings_segments_path
    segment = @alfa.segments.find_by!(name: "Atraso longo")
    assert_equal [ { "path" => "overdue_days", "op" => "gt", "value" => 90 } ], segment.expression["all"]
    assert_equal "Demais", tier_of(contract)
    assert Change.exists?(subject_type: "segment", subject_id: segment.id, event: "created", after: "contratos\n  atraso > 90")
  end

  test "R285, R290: o segmento novo em branco e o exemplo pronto abrem com o texto do sujeito, sem tradução faltando" do
    entrar(users(:joana))
    get new_settings_segment_path(tenant_id: @alfa.id)
    assert_select "textarea[name='segment[source]']", text: /\Acontratos\s*\z/
    assert_select "p.leitura", text: /Escreva as condições/
    assert_no_match(/Translation missing/, response.body)
    get new_settings_segment_path(tenant_id: @alfa.id, exemplo: "sem-contato-valido")
    assert_select "textarea[name='segment[source]']", text: /\Aclientes\s+sem contato válido\z/
    assert_no_match(/Translation missing/, response.body)
    segment = make_segment(@alfa, "Longo", min_overdue_days: 90)
    get edit_settings_segment_path(segment)
    assert_select "p.leitura strong", text: "Seleciona contratos em que o contrato tem atraso de pelo menos 90 dias."
    assert_no_match(/Translation missing/, response.body)
  end

  test "R301, R302: enquanto escreve, Como fica mostra a leitura de cada linha e os erros em português, sem gravar" do
    entrar(users(:joana))
    post draft_settings_segments_path(tenant_id: @alfa.id), params: { segment: { name: "X", source: text("contratos", "  atraso > 90", "  títulos vencidos 3", "  qualquer:", "    quebrou acordo") } }
    assert_response :success
    assert_select "aside#como-fica"
    assert_select "li[value='1'] p.leitura", text: "Seleciona contratos."
    assert_select "li[value='2'] p.leitura", text: "O contrato tem atraso maior que 90 dias."
    assert_select "li[value='3'][data-erro] p.erro", text: /\ALinha 3: vem uma comparação/
    assert_select "li[value='4'] p.leitura", text: "Pelo menos uma das linhas de baixo."
    assert_select "li[value='5'] p.leitura", text: "O contrato já quebrou acordo."
    assert_select "p.erro", text: "1 linha com erro."
    assert_equal 0, @alfa.segments.count
  end

  test "R303: com erro, não salva; o texto volta à caixa como estava e os erros aparecem" do
    entrar(users(:joana))
    post settings_segments_path, params: { tenant_id: @alfa.id, segment: { name: "Errado", source: text("contratos", "  atraso > noventa") } }
    assert_response :unprocessable_content
    assert_select "textarea[name='segment[source]']", text: /atraso > noventa/
    assert_select "p.erro", text: /"noventa" não é um número inteiro/
    assert_equal 0, @alfa.segments.count
  end

  test "R304: no segmento gravado, a primeira linha não muda" do
    segment = make_segment(@alfa, "Longo", min_overdue_days: 90)
    entrar(users(:joana))
    patch settings_segment_path(segment), params: { segment: { name: "Longo", source: text("clientes", "  tipo = PF") } }
    assert_response :unprocessable_content
    assert_select "p.erro", text: /seleciona contratos e isso não muda/
  end

  test "R288, revisão 3: Conferir roda em segundo plano e mostra o total e cada condição sozinha" do
    make_contract(@alfa, "C1", bills: [ { overdue: 120, cents: 100_000 } ])
    make_contract(@alfa, "C2", bills: [ { overdue: 10, cents: 50_000 } ])
    entrar(users(:joana))
    post probe_settings_segments_path(tenant_id: @alfa.id), params: { segment: { source: text("contratos", "  atraso > 90", "  saldo > R$ 5.000") } }
    assert_select "#conferir", text: /Contando/
    url = css_select("#conferir").first["hx-get"]
    perform_enqueued_jobs(only: SegmentProbeJob)
    get url
    assert_select "strong", text: "Pega 0 contratos"
    assert_select "td", text: "1"
    assert_select "td", text: "0 (zera)", count: 1
  end

  test "R272: mudar um segmento usado leva à conferência do impacto; confirmado, reclassifica e registra" do
    tier = make_tier(@alfa, "Longo", min_overdue_days: 100)
    contract = make_contract(@alfa, "C1", bills: [ { overdue: 50 } ])
    recalc(@alfa)
    entrar(users(:joana))
    patch settings_segment_path(tier.segment), params: { segment: { name: "Longo", source: text("contratos", "  atraso >= 30") } }
    follow_review
    assert_select "h2", text: "O que foi alterado"
    assert_select "code", text: /atraso >= 100/
    assert_select "code", text: /atraso >= 30/
    assert_equal "Demais", tier_of(contract), "nada muda antes de confirmar"
    confirm_review(@alfa)
    assert_equal "Longo", tier_of(contract)
  end

  test "R273: segmento sem uso se apaga; em uso, só se desativa, pela conferência" do
    free = make_segment(@alfa, "Livre")
    tier = make_tier(@alfa, "Usado")
    entrar(users(:joana))
    delete settings_segment_path(free)
    assert_redirected_to settings_segments_path
    assert_not Segment.exists?(free.id)
    delete settings_segment_path(tier.segment)
    assert_response :not_found
    delete settings_segment_activation_path(tier.segment)
    follow_review
    confirm_review(@alfa)
    assert_equal [ false, false ], [ tier.segment.reload.active, tier.reload.active ]
  end

  test "R289: o glossário vem do catálogo, com definição e exemplo" do
    entrar(users(:joana))
    get settings_segment_glossary_path
    assert_select "h2", text: "Coleções"
    assert_select "dt code", text: "atraso"
    assert_select "dd", text: /Dias desde o vencimento do título em cobrança mais atrasado do contrato/
    assert_no_match(/Translation missing/, response.body)
  end

  test "R293: incluir segmento oferece só os de contratos fora do enquadramento e leva à conferência" do
    make_segment(@alfa, "Clientes PF", subject: "customers", person_type: "person")
    contracts = make_segment(@alfa, "Longos", min_overdue_days: 90)
    make_tier(@alfa, "Já usado")
    entrar(users(:joana))
    get new_settings_tier_path(tenant_id: @alfa.id)
    assert_select "select[name='tier[segment_id]'] option", text: /Longos/
    assert_select "select[name='tier[segment_id]'] option", text: /Clientes PF|Já usado/, count: 0
    assert_select "small", text: /Segmentos de clientes não aparecem/
    post settings_tiers_path, params: { tenant_id: @alfa.id, tier: { segment_id: contracts.id, before_id: "", copy_from_id: Tier.catch_all_of(@alfa).id } }
    follow_review
    assert_select "h3", text: "Incluído no enquadramento: Longos"
    confirm_review(@alfa)
    assert Tier.financial.exists?(segment: contracts, active: true)
  end

  test "R292: o enquadramento mostra os itens em ordem, o Demais como trilha padrão, e mover leva à conferência" do
    a = make_tier(@alfa, "A", min_overdue_days: 1)
    make_tier(@alfa, "B", min_overdue_days: 5)
    entrar(users(:joana))
    get settings_tiers_path
    assert_select "span", text: "Trilha padrão"
    post settings_tier_movement_path(a), params: { movement: { direction: "down" } }
    follow_review
    assert_select "h3", text: "Ordem do enquadramento"
    confirm_review(@alfa)
    assert_equal [ "B", "A" ], Tier.financial.where(tenant: @alfa, catch_all: false, active: true).order(:position).map(&:name)
  end

  test "R272: as variáveis de acordo passam pela conferência antes de valer" do
    demais = Tier.catch_all_of(@alfa)
    entrar(users(:joana))
    patch settings_agreement_variables_path, params: { tenant_id: @alfa.id, tiers: { demais.id.to_s => { max_installments: "6", min_installment: "50,00", min_down_payment_pct: "10", down_payment_days: "10", validity_days: "5", tolerance_days: "3", break_days: "30" } } }
    follow_review
    assert_not_equal 6, demais.reload.agreement_max_installments
    confirm_review(@alfa)
    assert_equal 6, demais.reload.agreement_max_installments
  end

  test "R275, R296: a lista de clientes filtra por segmento de clientes e de contratos, e mostra a coluna Enquadramento" do
    make_tier(@alfa, "Longo", min_overdue_days: 90)
    maria = customer_of(@alfa, FakeData.cpf(1), "Maria")
    loja = customer_of(@alfa, CNPJ_A, "Loja Ltda")
    make_contract(@alfa, "C1", bills: [ { overdue: 120 } ], customers: [ maria ])
    make_contract(@alfa, "C2", bills: [ { overdue: 10 } ], customers: [ loja ])
    recalc(@alfa)
    pf = make_segment(@alfa, "PF", subject: "customers", person_type: "person")
    long = Tier.financial.find_by!(tenant: @alfa, catch_all: false).segment
    entrar(users(:joana))
    get customers_path
    assert_select "th", text: "Enquadramento"
    assert_select "optgroup[label='Segmentos de clientes'] option", text: "PF"
    get customers_path(segment: pf.id)
    assert_select "a", text: "Maria"
    assert_select "a", text: "Loja Ltda", count: 0
    get customers_path(segment: long.id)
    assert_select "td", text: "Longo"
    assert_select "a", text: "Loja Ltda", count: 0
  end

  test "revisão 3: segmento pesado demais para a lista mostra a mensagem" do
    segment = make_segment(@alfa, "Pesado")
    entrar(users(:joana))
    original = Segments::ListFilter.method(:load)
    Segments::ListFilter.define_singleton_method(:load) { |*| false }
    get customers_path(segment: segment.id)
    assert_select "p", text: /demora demais para a lista/
  ensure
    Segments::ListFilter.define_singleton_method(:load, original) if original
  end

  test "R297: a ficha mostra o enquadramento de cada contrato, desde quando e por quê" do
    make_tier(@alfa, "Longo", min_overdue_days: 90)
    contract = make_contract(@alfa, "C1", bills: [ { overdue: 120 } ])
    recalc(@alfa)
    entrar(users(:joana))
    get customer_path(contract.customers.first)
    assert_select "th", text: "Enquadramento"
    assert_select "td", text: /Longo/
    assert_select "tr.detalhe-da-linha p", text: /No item Longo do enquadramento financeiro desde/
  end

  test "R276 e V10: com a 14 na Alfa e só consulta na Beta, Marta vê a Beta sem botões e é recusada por envio direto, com registro" do
    marta = make_user(@alfa, %w[change_financial_policies change_settings])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Configura", permissions: %w[view_portfolio change_settings]))
    beta = make_segment(@beta, "Beta A")
    entrar(marta)
    get settings_segments_path
    assert_select "a", text: "Criar segmento", count: 1
    assert_difference -> { AccessEvent.where(event: "access_denied", tenant_id: @beta.id, user_id: marta.id).count }, 1 do
      post settings_segments_path, params: { tenant_id: @beta.id, segment: { name: "Y", source: text("contratos", "  atraso > 1") } }
      assert_response :not_found
    end
    patch settings_segment_path(beta), params: { segment: { name: "Mudado", source: text("contratos", "  atraso > 1") } }
    assert_response :not_found
    assert_equal "Beta A", beta.reload.name
  end
end
