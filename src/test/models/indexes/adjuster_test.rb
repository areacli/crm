require "test_helper"

# Correção de índice pelo credor (08, R145, R146): ajuste sobre o valor global, com motivo, valendo só para o credor que corrigiu.
class IndexesAdjusterTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @month = (Date.current - 2.months).beginning_of_month
    IndexRate.create!(series: "igpm", month: @month, value: "1.57", fetched_at: Time.current)
  end

  def adjuster(tenant = @alfa) = Indexes::Adjuster.new(users(:joana), tenant)

  test "R145 e R146 (critério de aceite): corrige 1,57 para 1,52 com motivo, a busca seguinte não muda, só a Alfa vê, e desfazer volta ao Banco Central" do
    adjuster.correct(series: "igpm", month: @month.strftime("%m/%Y"), value: "1,52", reason: "valor da FGV, divulgação de 29/09")
    adjustment = IndexAdjustment.find_by!(tenant: @alfa, series: "igpm", month: @month)
    assert_equal BigDecimal("1.52"), adjustment.value

    fake_bank(189 => [ [ @month.strftime("%d/%m/%Y"), "1.57" ] ])
    Indexes::Fetch.new.call
    assert_equal BigDecimal("1.57"), IndexRate.find_by!(series: "igpm", month: @month).value
    assert_equal BigDecimal("1.52"), IndexAdjustment.find_by!(tenant: @alfa, series: "igpm", month: @month).value
    assert_nil IndexAdjustment.find_by(tenant: @beta, series: "igpm", month: @month), "a Beta continua com o valor do Banco Central"

    change = Change.find_by!(subject_type: "index_adjustment", event: "corrected")
    assert_equal [ users(:joana), @alfa.id, "valor da FGV, divulgação de 29/09", "igpm" ], [ change.user, change.tenant_id, change.note, change.field ]
    assert_includes change.before, "1.57"
    assert_equal "1.52", change.after

    adjuster.undo(series: "igpm", month: @month.strftime("%m/%Y"), reason: "FGV republicou")
    assert_nil IndexAdjustment.find_by(tenant: @alfa, series: "igpm", month: @month)
    undone = Change.find_by!(subject_type: "index_adjustment", event: "correction_undone")
    assert_equal [ "FGV republicou", "1.57" ], [ undone.note, undone.after ]
  end

  test "R145 (critério de aceite): correção sem motivo é recusada com 'informe o motivo da correção'" do
    error = assert_raises(Indexes::Adjuster::Refused) { adjuster.correct(series: "igpm", month: @month.strftime("%m/%Y"), value: "1,52", reason: " ") }
    assert_equal "Informe o motivo da correção.", error.message
    assert_equal 0, IndexAdjustment.count
  end

  test "R145: um mês que não existe pode ser incluído; desfazer deixa o mês sem valor, sem apagar o Banco Central (revisão 1)" do
    older = (@month - 5.months)
    adjuster.correct(series: "ipca", month: older.strftime("%Y-%m"), value: "0,3", reason: "mês ausente na fonte")
    assert_equal BigDecimal("0.3"), IndexAdjustment.find_by!(tenant: @alfa, series: "ipca", month: older).value
    adjuster.undo(series: "ipca", month: older.strftime("%Y-%m"), reason: "era engano")
    assert_nil IndexRate.find_by(series: "ipca", month: older)
    assert_equal 0, IndexAdjustment.count
  end

  test "recusas: mês corrente, mês inválido, valor inválido e série desconhecida" do
    [ [ "ipca", Date.current.strftime("%m/%Y"), "1" ], [ "ipca", "13/2026", "1" ], [ "ipca", @month.strftime("%m/%Y"), "abc" ], [ "xyz", @month.strftime("%m/%Y"), "1" ] ].each do |series, month, value|
      assert_raises(Indexes::Adjuster::Refused, "#{series} #{month} #{value}") { adjuster.correct(series: series, month: month, value: value, reason: "x") }
    end
  end

  test "a correção transmite indexes-changed" do
    extend ActionCable::TestHelper
    assert_broadcasts(IndexesChannel.broadcasting_for("all"), 1) { adjuster.correct(series: "igpm", month: @month.strftime("%m/%Y"), value: "1,52", reason: "x") }
  end
end
