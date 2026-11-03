require "test_helper"

# A linguagem dos segmentos (13, R252 a R264, R278; decisão 0023): árvore validada contra o catálogo, texto curto e por extenso, e a tradução
# para consulta de conjunto, com todo valor como parâmetro e cada credor isolado.
class SegmentsLanguageTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  def expr(subject, *conditions) = Segments::Expression.new("grammar" => 1, "subject" => subject, "all" => conditions)

  def run_query(query) = ActiveRecord::Base.connection.select_all(query.sql, "Segments", query.binds).to_a

  def ids(tenant, expression) = run_query(Segments::Compiler.new(tenant).matching(expression)).map { |row| row["id"] }.sort

  def attempt(contract, result, days_ago)
    ContactAttempt.insert_all!([ { tenant_id: contract.tenant_id, customer_id: contract.customers.first.id, contract_id: contract.id, result_id: result.id,
                                   result_kind: result.kind, channel: "phone", contacted_at: days_ago.days.ago, created_at: Time.current, updated_at: Time.current } ])
  end

  def contact(customer, kind: "phone", status: "valid", city: nil, state: nil)
    CustomerContact.insert_all!([ { tenant_id: customer.tenant_id, customer_id: customer.id, kind: kind, key: SecureRandom.hex(4), value: "x", origin: "load",
                                    status: status, city: city, state: state, created_at: Time.current, updated_at: Time.current } ])
  end

  # Gramática e catálogo -----------------------------------------------------------------------------------------------------------------

  test "R254 e R255: árvore válida com atributo, coleção, agregação, quantificador, janela, pai e grupo qualquer" do
    expression = expr("contracts",
                      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 3 },
                      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "sum", "field" => "balance", "op" => "gt", "value" => 500_000 },
                      { "path" => "contact_attempts", "quantifier" => "none", "where" => { "field" => "result", "op" => "eq", "value" => 1 }, "within_days" => 30 },
                      { "path" => "holder.other_contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 1 },
                      { "any" => [ { "path" => "broke_agreement", "op" => "is" }, { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" }, "within_days" => 180 } ] })
    assert expression.valid?, expression.errors.inspect
    assert_equal 6, expression.count
  end

  test "R264: atributo fora do catálogo (nome, documento, telefone) é recusado" do
    %w[name document customer.document holder.name contacts.value].each do |path|
      expression = expr("contracts", { "path" => path, "op" => "eq", "value" => "x" })
      refute expression.valid?
      assert_equal [ "Atributo não disponível para segmentos." ], expression.errors["0"]
    end
  end

  test "R263: três níveis de navegação não existem; pai só a partir de contrato" do
    refute expr("contracts", { "path" => "holder.other_contracts.bills", "aggregate" => "count", "op" => "gte", "value" => 1 }).valid?
    refute expr("customers", { "path" => "holder.person_type", "op" => "eq", "value" => "person" }).valid?
  end

  test "casos de exceção: linha incompleta, faixa invertida, percentual acima de 100, janela em coleção sem data, mais de 20 condições" do
    assert_equal [ "Complete a condição." ], expr("contracts", { "path" => "overdue_days", "op" => "gt" }).tap(&:valid?).errors["0"]
    assert_equal [ "O primeiro valor tem de ser menor que o segundo." ], expr("contracts", { "path" => "overdue_days", "op" => "between", "value" => [ 90, 30 ] }).tap(&:valid?).errors["0"]
    assert_equal [ "O percentual vai de 0 a 100%." ], expr("contracts", { "path" => "overdue_percent", "op" => "gt", "value" => 120 }).tap(&:valid?).errors["0"]
    window = expr("contracts", { "path" => "bills", "aggregate" => "count", "op" => "gte", "value" => 1, "within_days" => 30 })
    refute window.valid?
    many = expr("contracts", *Array.new(21) { { "path" => "overdue_days", "op" => "gt", "value" => 1 } })
    refute many.valid?
    assert_includes many.errors["base"], "Um segmento tem no máximo 20 condições; divida em dois segmentos."
  end

  test "R254: grupo qualquer tem um nível só" do
    nested = expr("contracts", { "any" => [ { "any" => [ { "path" => "in_arrears", "op" => "is" } ] } ] })
    refute nested.valid?
  end

  # Texto curto e por extenso (R278, SG13, SG14) -------------------------------------------------------------------------------------------

  test "R278: texto curto e leitura por extenso dos exemplos da especificação" do
    result = contact_results(:alfa_promised)
    expression = expr("contracts",
                      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 3 },
                      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "sum", "field" => "balance", "op" => "gt", "value" => 500_000 },
                      { "path" => "contact_attempts", "quantifier" => "none", "where" => { "field" => "result", "op" => "eq", "value" => result.id }, "within_days" => 30 },
                      { "path" => "holder.other_contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 1 })
    text = Segments::Text.new(expression)
    assert_equal [ "contratos", "títulos vencidos >= 3", "soma saldo títulos vencidos > R$ 5.000",
                   "nenhum acionamento \"#{result.name}\" em 30 dias", "titular outros contratos em atraso >= 1" ], text.lines.map(&:short)
    assert_equal "o contrato tem pelo menos 3 títulos vencidos", text.lines[1].long
    assert_equal "o contrato não tem nenhum acionamento com resultado igual a \"#{result.name}\" nos últimos 30 dias", text.lines[3].long
  end

  test "SG14: atalho entre aspas pelo campo principal; outros campos com 'com'; concordância e 'sem'" do
    text = Segments::Text.new(expr("contracts",
                                   { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" }, "within_days" => 180 },
                                   { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "in", "value" => [ "Cartão", "Crédito" ] } },
                                   { "path" => "bills", "quantifier" => "all", "where" => { "field" => "kind", "op" => "eq", "value" => "agreement" } },
                                   { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" }))
    assert_equal [ "alguma promessa \"quebrada\" em 180 dias", "algum título \"Cartão\", \"Crédito\"", "todos os títulos com tipo = acordo", "sem contato válido" ],
                 text.lines.drop(1).map(&:short)
  end

  test "R278: atributos, pai, negação, faixa, lista e o grupo qualquer" do
    text = Segments::Text.new(expr("contracts",
                                   { "path" => "produto".then { "product" }, "op" => "eq", "value" => "Mensalidade" },
                                   { "path" => "overdue_days", "op" => "between", "value" => [ 30, 90 ] },
                                   { "path" => "holder.person_type", "op" => "eq", "value" => "company" },
                                   { "path" => "broke_agreement", "op" => "is", "negate" => true },
                                   { "any" => [ { "path" => "overdue_percent", "op" => "gte", "value" => 80 }, { "path" => "person_type", "op" => "in", "value" => %w[person mixed] } ] }))
    assert_equal "contratos\n  produto = Mensalidade\n  atraso entre 30 e 90\n  titular tipo = PJ\n  não quebrou acordo\n  qualquer:\n    % vencido >= 80%\n    tipo em PF, misto", text.short_text
    assert_equal "o contrato tem atraso entre 30 dias e 90 dias", text.lines[2].long
    assert_equal "algum titular tem tipo igual a pessoa jurídica", text.lines[3].long
    assert_equal "o contrato nunca quebrou acordo", text.lines[4].long
    assert_match(/\ASeleciona contratos em que o contrato tem produto igual a Mensalidade; e /, text.long_text)
  end

  test "texto curto distingue árvores diferentes (base do analisador futuro)" do
    variants = [
      { "path" => "bills", "aggregate" => "count", "op" => "gte", "value" => 3 },
      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 3 },
      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gt", "value" => 3 },
      { "path" => "bills", "qualifier" => "overdue", "aggregate" => "sum", "field" => "balance", "op" => "gte", "value" => 3 },
      { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "eq", "value" => "3" } },
      { "path" => "bills", "quantifier" => "none", "where" => { "field" => "product", "op" => "eq", "value" => "3" } },
      { "path" => "bills", "quantifier" => "all", "where" => { "field" => "product", "op" => "eq", "value" => "3" } },
      { "path" => "overdue_days", "op" => "gte", "value" => 3 },
      { "path" => "holder.overdue_days", "op" => "gte", "value" => 3 },
      { "path" => "overdue_days", "op" => "gte", "value" => 3, "negate" => true }
    ]
    texts = variants.map { |node| Segments::Text.new(expr("contracts", node)).short_text }
    assert_equal texts.size, texts.uniq.size, texts.inspect
  end

  # Tradução para consulta (0023, seção 3) ----------------------------------------------------------------------------------------------

  test "R255: atributos de hoje com a definição da 08 (atraso, saldo, % vencido, tipo, produto)" do
    maria = make_contract(@alfa, "C-MARIA", bills: [ { overdue: 40, cents: 120_000, product: "Mensalidade" }, { overdue: -10, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(1)) ])
    loja = make_contract(@alfa, "C-LOJA", bills: [ { overdue: 200, cents: 530_000, product: "Cartão" }, { overdue: -5, cents: 100_000 } ], customers: [ customer_of(@alfa, SegmentsTestHelper::CNPJ_A) ])
    assert_equal [ maria.id ], ids(@alfa, expr("contracts", { "path" => "overdue_days", "op" => "between", "value" => [ 1, 90 ] }))
    assert_equal [ loja.id ], ids(@alfa, expr("contracts", { "path" => "balance", "op" => "gt", "value" => 500_000 }))
    assert_equal [ loja.id ], ids(@alfa, expr("contracts", { "path" => "overdue_percent", "op" => "gte", "value" => 80 }))
    assert_equal [ maria.id ], ids(@alfa, expr("contracts", { "path" => "person_type", "op" => "eq", "value" => "person" }))
    assert_equal [ loja.id ], ids(@alfa, expr("contracts", { "path" => "product", "op" => "eq", "value" => "cartao" }))
    assert_equal [ maria.id ], ids(@alfa, expr("contracts", { "path" => "product", "op" => "ne", "value" => "Cartão" }))
  end

  test "R258 e SG12: títulos sem qualificador são os em aberto; qualificadores vencidos e a vencer; soma e maior" do
    four = make_contract(@alfa, "C-4", bills: [ { overdue: 5 }, { overdue: 6 }, { overdue: 7 }, { overdue: 8 }, { overdue: -20 } ])
    two = make_contract(@alfa, "C-2", bills: [ { overdue: 5 }, { overdue: 6, paid: 100_000 }, { overdue: -20 } ])
    two.bills.where(paid_cents: 100_000).update_all(status: "paid")
    assert_equal [ four.id ], ids(@alfa, expr("contracts", { "path" => "bills", "aggregate" => "count", "op" => "gte", "value" => 5 }))
    assert_equal [ four.id ], ids(@alfa, expr("contracts", { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "between", "value" => [ 3, 10 ] }))
    assert_equal [ four.id, two.id ].sort, ids(@alfa, expr("contracts", { "path" => "bills", "qualifier" => "due", "aggregate" => "count", "op" => "eq", "value" => 1 }))
    assert_equal [ four.id ], ids(@alfa, expr("contracts", { "path" => "bills", "qualifier" => "overdue", "aggregate" => "sum", "field" => "balance", "op" => "gt", "value" => 200_000 }))
    assert_equal [ four.id, two.id ].sort, ids(@alfa, expr("contracts", { "path" => "bills", "aggregate" => "max", "field" => "overdue_days", "op" => "gte", "value" => 5 }))
  end

  test "R254: algum, todos e nenhum; 'todos' exige ao menos um item" do
    cards = make_contract(@alfa, "C-CARD", bills: [ { overdue: 5, product: "Cartão" }, { overdue: 9, product: "cartao" } ])
    mixed = make_contract(@alfa, "C-MIX", bills: [ { overdue: 5, product: "Cartão" }, { overdue: 9, product: "Empréstimo" } ])
    paid = make_contract(@alfa, "C-PAID", bills: [ { overdue: 5, product: "Cartão", paid: 100_000 } ])
    paid.bills.update_all(status: "paid")
    some = { "path" => "bills", "quantifier" => "some", "where" => { "field" => "product", "op" => "eq", "value" => "Cartão" } }
    assert_equal [ cards.id, mixed.id ].sort, ids(@alfa, expr("contracts", some))
    assert_equal [ cards.id ], ids(@alfa, expr("contracts", some.merge("quantifier" => "all")))
    assert_equal [ paid.id ], ids(@alfa, expr("contracts", some.merge("quantifier" => "none")))
  end

  test "R259 e R262: acionamento com resultado dentro da janela de dias" do
    result = contact_results(:alfa_promised)
    recent = make_contract(@alfa, "C-REC", bills: [ { overdue: 10 } ])
    old = make_contract(@alfa, "C-OLD", bills: [ { overdue: 10 } ])
    attempt(recent, result, 12)
    attempt(old, result, 31)
    none = { "path" => "contact_attempts", "quantifier" => "none", "where" => { "field" => "result", "op" => "eq", "value" => result.id }, "within_days" => 30 }
    assert_equal [ old.id ], ids(@alfa, expr("contracts", none))
    assert_equal [ recent.id ], ids(@alfa, expr("contracts", none.merge("quantifier" => "some")))
  end

  test "R257 e R263: pai do contrato e outros contratos do titular, sem o próprio" do
    ana = customer_of(@alfa, FakeData.cpf(31))
    first = make_contract(@alfa, "C-A1", bills: [ { overdue: 10 } ], customers: [ ana ])
    second = make_contract(@alfa, "C-A2", bills: [ { overdue: -10 } ], customers: [ ana ])
    alone = make_contract(@alfa, "C-B1", bills: [ { overdue: 10 } ], customers: [ customer_of(@alfa, FakeData.cpf(32)) ])
    others = { "path" => "holder.other_contracts", "qualifier" => "in_arrears", "aggregate" => "count", "op" => "gte", "value" => 1 }
    assert_equal [ second.id ], ids(@alfa, expr("contracts", others))
    assert_equal [ first.id, second.id, alone.id ].sort, ids(@alfa, expr("contracts", { "path" => "holder.person_type", "op" => "eq", "value" => "person" }))
  end

  test "R260: contatos do cliente, 'sem contato válido', UF e cidade" do
    a = customer_of(@alfa, FakeData.cpf(41))
    b = customer_of(@alfa, FakeData.cpf(42))
    c = customer_of(@alfa, FakeData.cpf(43))
    contact(a, status: "invalid")
    contact(b, kind: "address", status: "valid", city: "São Paulo", state: "SP")
    without = { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" }
    assert_equal [ a.id, c.id ].sort, ids(@alfa, expr("customers", without))
    assert_equal [ b.id ], ids(@alfa, expr("customers", { "path" => "contacts", "quantifier" => "some", "where" => { "field" => "city", "op" => "eq", "value" => "sao paulo" } }))
  end

  test "R256: segmento de clientes pelo maior atraso dos contratos" do
    ana = customer_of(@alfa, FakeData.cpf(51))
    make_contract(@alfa, "C-X1", bills: [ { overdue: 120 } ], customers: [ ana ])
    make_contract(@alfa, "C-X2", bills: [ { overdue: 10 } ], customers: [ customer_of(@alfa, FakeData.cpf(52)) ])
    assert_equal [ ana.id ], ids(@alfa, expr("customers", { "path" => "overdue_days", "op" => "gt", "value" => 90 }, { "path" => "person_type", "op" => "eq", "value" => "person" }))
  end

  test "R267, revisão 6: o enquadramento escolhe o primeiro item que casa; quem não casa fica no padrão; não há regra de entrada" do
    long = make_contract(@alfa, "C-L", bills: [ { overdue: 200 } ])
    short = make_contract(@alfa, "C-S", bills: [ { overdue: 10 } ])
    paid = make_contract(@alfa, "C-P", bills: [ { overdue: 10, paid: 100_000 } ])
    paid.bills.update_all(status: "paid")
    entries = [ [ 11, expr("contracts", { "path" => "overdue_days", "op" => "gt", "value" => 90 }) ], [ 12, expr("contracts", { "path" => "overdue_days", "op" => "gt", "value" => 0 }) ] ]
    rows = run_query(Segments::Compiler.new(@alfa).classify(entries, default_id: 99)).to_h { |row| [ row["contract_id"], row["tier_id"] ] }
    assert_equal({ long.id => 11, short.id => 12, paid.id => 99 }, rows)
    rows = run_query(Segments::Compiler.new(@alfa).classify([], default_id: 99)).to_h { |row| [ row["contract_id"], row["tier_id"] ] }
    assert_equal({ long.id => 99, short.id => 99, paid.id => 99 }, rows)
  end

  test "13, revisão 6: \"em cobrança\" separa quem tem título em cobrança, vencido ou a vencer" do
    overdue = make_contract(@alfa, "C-V", bills: [ { overdue: 10 } ])
    due = make_contract(@alfa, "C-AV", bills: [ { overdue: -5 } ])
    paid = make_contract(@alfa, "C-PG", bills: [ { overdue: 10 } ])
    paid.bills.update_all(status: "paid")
    entries = [ [ 1, expr("contracts", { "path" => "in_collection", "op" => "is" }) ] ]
    rows = run_query(Segments::Compiler.new(@alfa).classify(entries, default_id: 0)).to_h { |row| [ row["contract_id"], row["tier_id"] ] }
    assert_equal({ overdue.id => 1, due.id => 1, paid.id => 0 }, rows)
    assert_equal [ paid.id ], ids(@alfa, expr("contracts", { "path" => "in_collection", "op" => "is", "negate" => true }))
  end

  test "R288: conferir conta o total e cada condição sozinha" do
    make_contract(@alfa, "C-1", bills: [ { overdue: 200, cents: 100_000 } ])
    make_contract(@alfa, "C-2", bills: [ { overdue: 10, cents: 50_000 } ])
    expression = expr("contracts", { "path" => "overdue_days", "op" => "gt", "value" => 90 }, { "path" => "balance", "op" => "gt", "value" => 500_000 })
    compiler = Segments::Compiler.new(@alfa)
    row = run_query(compiler.probe(expression)).first
    assert_equal [ 0, 1, 0 ], [ row["total"], row["c0"], row["c1"] ]
    assert_equal %w[0 1], compiler.probe_addresses
  end

  test "V10: cada credor só vê os próprios contratos, e nenhum valor da árvore entra no texto da consulta" do
    mine = make_contract(@alfa, "C-ALFA", bills: [ { overdue: 10, product: "Robert'); drop table bills;--" } ])
    make_contract(@beta, "C-BETA", bills: [ { overdue: 10, product: "Robert'); drop table bills;--" } ])
    expression = expr("contracts", { "path" => "product", "op" => "eq", "value" => "Robert'); drop table bills;--" },
                      { "path" => "overdue_days", "op" => "gte", "value" => 987_654 }.merge("op" => "lte"))
    query = Segments::Compiler.new(@alfa).matching(expression)
    refute_includes query.sql, "drop table"
    refute_includes query.sql, "987654"
    assert_equal [ mine.id ], run_query(query).map { |row| row["id"] }
  end
end
