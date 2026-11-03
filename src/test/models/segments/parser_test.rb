require "test_helper"

# O analisador da linguagem (13, revisão 4, R301 a R304): o texto que a tela escreve volta à mesma árvore, sem diferença de maiúsculas, acentos e
# espaços; cada problema dá um erro em português com a linha.
class SegmentsParserTest < ActiveSupport::TestCase
  setup { @alfa = tenants(:alfa) }

  def parse(text, subject: nil) = Segments::Parser.new(@alfa, subject: subject).parse(text)

  def tree_of(subject, *nodes) = { "grammar" => 1, "subject" => subject, "all" => nodes }

  test "R301: o texto curto da tela volta à mesma árvore (ida e volta) para todo tipo de condição" do
    result = contact_results(:alfa_promised)
    trees = [
      tree_of("contracts", { "path" => "overdue_days", "op" => "gt", "value" => 90 }),
      tree_of("contracts", { "path" => "overdue_days", "op" => "between", "value" => [ 30, 90 ] }, { "path" => "balance", "op" => "lte", "value" => 500_050 }),
      tree_of("contracts", { "path" => "person_type", "op" => "in", "value" => %w[person mixed] }, { "path" => "product", "op" => "eq", "value" => "Mensalidade" }),
      tree_of("contracts", { "path" => "broke_agreement", "op" => "is", "negate" => true }, { "path" => "in_arrears", "op" => "is" }),
      tree_of("contracts", { "path" => "in_collection", "op" => "is" }, { "path" => "in_arrears", "op" => "is", "negate" => true }),
      tree_of("customers", { "path" => "contracts", "qualifier" => "in_collection", "aggregate" => "count", "op" => "gte", "value" => 1 }),
      tree_of("contracts", { "path" => "overdue_percent", "op" => "gte", "value" => 80 }, { "path" => "overdue_days", "op" => "gt", "value" => 10, "negate" => true }),
      tree_of("contracts", { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 3 },
              { "path" => "bills", "qualifier" => "overdue", "aggregate" => "sum", "field" => "balance", "op" => "gt", "value" => 500_000 }),
      tree_of("contracts", { "path" => "contact_attempts", "quantifier" => "none", "where" => { "field" => "result", "op" => "eq", "value" => result.id }, "within_days" => 30 }),
      tree_of("contracts", { "path" => "holder.other_contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 1 },
              { "path" => "holder.person_type", "op" => "eq", "value" => "company" }),
      tree_of("contracts", { "any" => [ { "path" => "broke_agreement", "op" => "is" }, { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" }, "within_days" => 180 } ] }),
      tree_of("contracts", { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "in", "value" => [ "Cartão", "Crédito" ] } },
              { "path" => "bills", "quantifier" => "all", "where" => { "field" => "kind", "op" => "eq", "value" => "agreement" } }),
      tree_of("contracts", { "path" => "bills", "aggregate" => "max", "field" => "overdue_days", "op" => "gte", "value" => 5 }, { "path" => "customers", "aggregate" => "count", "op" => "gte", "value" => 2 }),
      tree_of("contracts", { "path" => "payments", "aggregate" => "sum", "field" => "amount", "op" => "lte", "value" => 100_000, "within_days" => 120 }),
      tree_of("customers", { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" }, { "path" => "customer_days", "op" => "gte", "value" => 30 }),
      tree_of("customers", { "path" => "contacts", "quantifier" => "some", "where" => { "field" => "city", "op" => "eq", "value" => "São Paulo" } }, { "path" => "overdue_days", "op" => "gt", "value" => 90 })
    ]
    trees.each do |tree|
      text = Segments::Text.new(Segments::Expression.new(tree)).short_text
      parsed = parse(text)
      assert parsed.ok?, "#{text}\n#{parsed.errors.inspect}"
      assert_equal tree, parsed.tree, text
    end
  end

  test "R301: maiúsculas, acentos e espaços não mudam nada; dinheiro e percentual com ou sem símbolo" do
    loose = parse("CONTRATOS\n   titulos   vencidos >= 3\n  SOMA saldo titulos vencidos > 5.000,50\n  % vencido >= 80%")
    strict = parse("contratos\n  títulos vencidos >= 3\n  soma saldo títulos vencidos > R$ 5.000,50\n  % vencido >= 80")
    assert loose.ok?, loose.errors.inspect
    assert_equal strict.tree, loose.tree
  end

  test "R302: erro em português com a linha e o que se esperava" do
    result = parse("contratos\n  atraso > 90\n  títulos vencidos 3\n  atraso > noventa\n  cor = azul")
    assert_equal [ 3, 4, 5 ], result.errors.map(&:first)
    assert_match(/\ALinha 3: vem uma comparação/, result.errors[0].last)
    assert_match(/"noventa" não é um número inteiro/, result.errors[1].last)
    assert_match(/não reconheci o começo/, result.errors[2].last)
    assert_nil result.tree
  end

  test "R304: a primeira linha é o sujeito; no segmento gravado, ela não muda" do
    assert_match(/primeira linha diz o que o segmento seleciona/, parse("pessoas\n  atraso > 1").errors.first.last)
    assert_match(/seleciona contratos e isso não muda/, parse("clientes\n  tipo = PF", subject: "contracts").errors.first.last)
  end

  test "casos de exceção: grupo vazio, janela em coleção sem data, resultado que não existe, faixa invertida (validação do catálogo)" do
    assert_match(/grupo "qualquer:"/, parse("contratos\n  qualquer:\n  atraso > 1").errors.first.last)
    assert_match(/em N dias/, parse("contratos\n  títulos >= 1 em 30 dias").errors.first.last)
    assert_match(/não há resultado de acionamento chamado "Inventado"/, parse("contratos\n  nenhum acionamento \"Inventado\"").errors.first.last)
    assert_equal [ 2, "O primeiro valor tem de ser menor que o segundo." ], parse("contratos\n  atraso entre 90 e 30").errors.first
  end
end
