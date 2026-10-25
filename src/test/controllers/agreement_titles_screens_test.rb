require "test_helper"

# Telas dos títulos do acordo, da quitação, da quebra manual e do arquivo de acordos (11, R221 a R238, R244, R245), com V10.
class AgreementTitlesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366) ])
    @agreement.reload
  end

  teardown { travel_back }

  def entrar(user, password = "senha-de-teste-1")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "R221, R225: a página do acordo efetivado mostra os títulos de acordo, o devido de hoje e a situação" do
    entrar(users(:carlos))
    get agreement_path(@agreement)

    assert_response :success
    assert_select "h2", text: "Títulos de acordo"
    assert_select "table th a", text: "ACD-000001-02"
    assert_select "td", text: "R$ 311,33"
    assert_select "td", text: "Pago"
    assert_select "td", text: "A vencer"
  end

  test "R225: a ficha mostra o título de acordo com a marca, os originais renegociados e o saldo do acordo" do
    entrar(users(:carlos))
    get customer_path(@customer)

    assert_response :success
    assert_select "small", text: /Título de acordo/
    assert_select "small", text: /Renegociado no acordo/
    assert_select "td", text: "Renegociado"
    assert_select "td", text: "Pago"
  end

  test "R230: 'Calcular quitação' grava o saldo para a data e a página o mostra" do
    entrar(users(:carlos))
    post agreement_settlement_path(@agreement), params: { settlement: { on_date: "2026-12-31" } }
    assert_redirected_to agreement_path(@agreement)

    quote = @agreement.settlements.last
    assert_equal Date.new(2026, 12, 31), quote.on_date
    follow_redirect!
    assert_select "li", text: /Quitação calculada para 31\/12\/2026/
    post agreement_settlement_path(@agreement), params: { settlement: { on_date: "2020-01-01" } }
    assert_equal I18n.t("agreements.settlements.create.invalid_date"), flash[:alert]
  end

  test "R238, R245: a quebra manual é de quem administra acordos; quem só negocia não vê a ação e recebe 'não encontrado'" do
    entrar(users(:carlos))
    get agreement_path(@agreement)
    assert_select "summary", text: "Quebrar o acordo", count: 0
    post agreement_break_path(@agreement), params: { break: { reason: "x", fraud: "1" } }
    assert_response :not_found
    delete session_path

    entrar(users(:joana))
    get agreement_path(@agreement)
    assert_select "summary", text: "Quebrar o acordo"
    post agreement_break_path(@agreement), params: { break: { reason: "documento falso", fraud: "1" } }
    assert_predicate @agreement.reload, :state_broken?
    follow_redirect!
    assert_select "aside", text: /Acordo quebrado em/
  end

  test "R238: sem atraso e sem fraude a quebra manual é recusada com a mensagem" do
    entrar(users(:joana))
    post agreement_break_path(@agreement), params: { break: { reason: "só porque sim" } }

    assert_equal I18n.t("agreements.refused.not_late"), flash[:alert]
    assert_predicate @agreement.reload, :state_active_on_time?
  end

  test "R244: o arquivo de acordos exporta as quatro linhas e fica registrado; só quem administra acordos vê e baixa" do
    entrar(users(:carlos))
    get agreement_exports_path
    assert_response :not_found
    delete session_path

    entrar(users(:joana))
    get agreement_exports_path
    assert_response :success
    post agreement_exports_path, params: { agreement_export: { tenant_id: @alfa.id, form: "full" } }
    assert_redirected_to agreement_exports_path
    export = AgreementExport.last
    assert_equal [ "full", users(:joana) ], [ export.form, export.user ]

    get agreement_export_path(export)
    assert_response :success
    rows = CSV.parse(response.body, col_sep: ";", headers: true)
    assert_equal %w[acordo divida divida evento evento titulo_de_acordo titulo_de_acordo titulo_de_acordo titulo_de_acordo titulo_de_acordo].sort, rows.map { |row| row["tipo"] }.sort
    assert_equal [ "ACD-000001" ], rows.select { |row| row["tipo"] == "acordo" }.map { |row| row["acordo"] }
    assert_equal %w[aceito efetivado], rows.select { |row| row["tipo"] == "evento" }.map { |row| row["evento"] }.sort
    paid = rows.find { |row| row["titulo"] == "ACD-000001-00" }
    assert_equal [ "pago", "34366" ], [ paid["situacao"], paid["valor"] ]
    parcel = rows.find { |row| row["titulo"] == "ACD-000001-02" }
    assert_equal [ "2.0", "1.0", "thirty" ], [ parcel["multa_pct"], parcel["taxa_juros_atraso"], parcel["convencao_juros"] ]
  end

  test "R244: as novidades levam só o que aconteceu desde a última exportação manual, e o arquivo do dia não muda o marco" do
    archive = Agreements::Archive.new(@alfa)
    first = archive.export!("news", user: users(:joana))
    assert_operator first.lines, :>, 0
    second = archive.export!("news", user: users(:joana))
    assert_equal 0, second.lines, "nada de novo desde a última exportação"

    daily = archive.export!("daily", today: Date.current)
    assert_equal first.last_event_id, daily.last_event_id.then { |id| id.zero? ? first.last_event_id : id }
    assert_operator daily.lines, :>, 0, "o arquivo do dia leva o que aconteceu hoje"
    pay_lines([ pay_line("ACD-000001-01", Date.new(2026, 11, 4), 100) ])
    assert_equal second.last_event_id, AgreementExport.manual.maximum(:last_event_id)
  end

  test "R244: os arquivos duram 30 dias e depois são apagados" do
    export = Agreements::Archive.new(@alfa).export!("full", user: users(:joana))
    assert export.available?
    export.update_columns(created_at: 31.days.ago)
    AgreementExport.purge!

    assert_nil export.reload.file_name
    assert_not export.available?
  end

  test "V10: o acordo de outro credor não abre, não calcula quitação, não quebra e não exporta" do
    outsider = make_user(@beta, %w[negotiate_agreements administer_agreements])
    entrar(outsider)
    get agreement_path(@agreement)
    assert_response :not_found
    post agreement_settlement_path(@agreement), params: { settlement: { on_date: "2026-12-31" } }
    assert_response :not_found
    post agreement_break_path(@agreement), params: { break: { reason: "x", fraud: "1" } }
    assert_response :not_found
    post agreement_exports_path, params: { agreement_export: { tenant_id: @alfa.id, form: "full" } }
    assert_response :not_found
    get agreement_exports_path
    assert_response :success
    assert_no_match(/ACD-000001/, response.body)
  end
end
