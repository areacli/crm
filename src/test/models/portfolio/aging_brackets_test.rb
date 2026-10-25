require "test_helper"

class Portfolio::AgingBracketsTest < ActiveSupport::TestCase
  DEFAULT = TenantSetting::DEFAULT_BRACKETS

  test "as faixas iniciais cobrem de 1 dia a mais de 360 (R18)" do
    brackets = Portfolio::AgingBrackets.from(DEFAULT)

    assert_equal [ "1–30", "31–60", "61–90", "91–180", "181–360", "mais de 360" ], brackets.labels
    assert_nil brackets.index_for(0)
    assert_equal 0, brackets.index_for(1)
    assert_equal 1, brackets.index_for(38)
    assert_equal 3, brackets.index_for(95)
    assert_equal 5, brackets.index_for(4000)
  end

  test "recusa faixa que não começa em 1, com buraco, sobreposição, sem fim aberto ou com fim antes do início" do
    {
      [ { from: 2, to: nil } ] => /começam em 1/,
      [ { from: 1, to: 30 }, { from: 40, to: nil } ] => /buraco entre as faixas: 31 a 39/,
      [ { from: 1, to: 30 }, { from: 30, to: nil } ] => /sobrepostas/,
      [ { from: 1, to: 30 }, { from: 31, to: 60 } ] => /última faixa deve ser aberta/,
      [ { from: 1, to: nil }, { from: 31, to: nil } ] => /só a última faixa pode ser aberta/,
      [ { from: 1, to: 0 }, { from: 1, to: nil } ] => /.+/,
      [] => /ao menos uma faixa/
    }.each do |input, message|
      error = assert_raises(Portfolio::InvalidBrackets, input.inspect) { Portfolio::AgingBrackets.from(input) }
      assert_match message, error.message
    end
  end

  test "aceita faixas guardadas em texto (jsonb) e fora de ordem" do
    brackets = Portfolio::AgingBrackets.from([ { "from" => "31", "to" => nil }, { "from" => "1", "to" => "30" } ])

    assert_equal [ "1–30", "mais de 30" ], brackets.labels
  end

  test "a expressão SQL dá o mesmo índice que o Ruby" do
    brackets = Portfolio::AgingBrackets.from(DEFAULT)
    sql = brackets.sql_index("d")
    [ 1, 30, 31, 60, 61, 95, 181, 361, 900 ].each do |days|
      indice = Portfolio::Sql.one("select #{sql} as i from (select #{days} as d) t")["i"]

      assert_equal brackets.index_for(days), indice.to_i, "dias #{days}"
    end
  end
end
