require "test_helper"

# Dados pessoais dos acordos (11, R247, R132, R130): o acordo em andamento é relação em aberto e recusa a anonimização; o encerrado perde nome e documento do termo guardado.
class Agreements::PrivacyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
  end

  teardown { travel_back }

  def pay(day, number, cents)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents) ])
  end

  def settle_everything
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    pay(Date.new(2027, 1, 5), "ACD-000001-02", 31_133)
    pay(Date.new(2027, 2, 5), "ACD-000001-03", 31_133)
    pay(Date.new(2027, 3, 5), "ACD-000001-04", 31_134)
    @agreement.reload
  end

  test "R247, R130: o acordo aguardando efetivação ou ativo é relação em aberto e recusa a anonimização, dizendo qual" do
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    relations = Titular::OpenRelations.new(@customer)

    assert_includes relations.message, "acordo ACD-000001 em andamento"
    error = assert_raises(Titular::Refused) { Titular::Anonymizer.on_request(@customer, actor: users(:joana), reason: "pedido", document: @customer.document) }
    assert_includes error.message, "acordo ACD-000001"
  end

  test "R247, R132: com o acordo quitado, a anonimização troca nome e documento no termo guardado e nos motivos; valores, datas e números ficam" do
    settle_everything
    assert_predicate @agreement, :state_settled?
    @agreement.update_columns(reason: "motivo com nome Maria Souza")
    snapshot_before = @agreement.term_snapshot
    assert_equal "Maria Souza", snapshot_before["customer"]["name"]

    Titular::Anonymizer.on_request(@customer.reload, actor: users(:joana), reason: "pedido do titular", document: @customer.document)

    @agreement.reload
    assert_equal "Cliente anonimizado nº #{@customer.id}", @agreement.term_snapshot["customer"]["name"]
    assert_not_includes @agreement.term_snapshot.to_json, "529.982.247-25"
    assert_not_includes @agreement.term_snapshot.to_json, "Maria Souza"
    assert_equal Titular::Anonymizer::REMOVED, @agreement.reason
    assert_equal snapshot_before["total_cents"], @agreement.term_snapshot["total_cents"]
    assert_equal "ACD-000001", @agreement.number
    assert_equal 5, @agreement.titles.count
  end

  test "R127: a exportação dos dados do cliente traz os acordos" do
    data = Titular::Exporter.new(@customer).to_h
    assert_equal [ "ACD-000001" ], data[:acordos].map { |item| item[:numero] }
    assert_equal %w[NF-1 NF-2], data[:acordos].first[:titulos].sort
  end
end
