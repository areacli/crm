require "test_helper"

# Datas de Brasília no banco (correção da camada 15c): o banco guarda instantes em UTC e `coluna::date` daria a data de lá; depois das 21h de Brasília ela já é a do dia seguinte.
# Os testes rodam com o relógio às 22h30 de Brasília (01h30 de UTC do dia seguinte).
class SupportDatesTest < ActiveSupport::TestCase
  setup { @alfa = tenants(:alfa) }

  test "BrDate.sql_date converte o instante na data de Brasília, também depois das 21h" do
    instant = Time.find_zone("Brasilia").local(2026, 11, 30, 22, 30)
    row = Portfolio::Sql.one("select #{BrDate.sql_date('?::timestamptz')} as d, (?::timestamptz)::date as utc", instant, instant)

    assert_equal Date.new(2026, 11, 30), Date.parse(row["d"].to_s)
    assert_equal Date.new(2026, 12, 1), Date.parse(row["utc"].to_s), "com a data de UTC o dia seria o seguinte"
  end

  test "a última movimentação do crédito, nos fatos do titular, é a data de Brasília" do
    contract = Contract.create!(tenant: @alfa, code: "CT-NOITE")
    Credit.create!(tenant: @alfa, contract: contract, kind: :entry, amount_cents: 1_000, reason: :excess, occurred_at: Time.find_zone("Brasilia").local(2026, 11, 30, 22, 30))
    row = Portfolio::Sql.one("with #{Titular::Facts.sql(contract_ids: [ contract.id ])} select last_on from facts")

    assert_equal Date.new(2026, 11, 30), Date.parse(row["last_on"].to_s)
  end
end
