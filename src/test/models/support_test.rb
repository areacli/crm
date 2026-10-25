require "test_helper"

class SupportTest < ActiveSupport::TestCase
  test "o documento é identificado sem máscara e confere os dígitos verificadores (R1, R2)" do
    assert_equal "52998224725", Document.normalize("529.982.247-25")
    assert_nil Document.problem("529.982.247-25")
    assert_nil Document.problem("52998224725")
    assert_equal "CPF inválido", Document.problem("111.111.111-11")
    assert_equal "CPF inválido", Document.problem("529.982.247-24")
    assert_nil Document.problem("11.222.333/0001-81")
    assert_equal "CNPJ inválido", Document.problem("11.222.333/0001-82")
    assert_match(/documento inválido/, Document.problem("123"))
  end

  test "o CNPJ alfanumérico é aceito quando o dígito verificador confere" do
    assert_nil Document.problem("12.ABC.345/01DE-35")
    assert_equal "CNPJ inválido", Document.problem("12.ABC.345/01DE-36")
  end

  test "máscara da lista e formato da ficha" do
    assert_equal "529.***.***-25", Document.mask("52998224725")
    assert_equal "11.***.***/****-81", Document.mask("11222333000181")
    assert_equal "529.982.247-25", Document.format("52998224725")
    assert_equal "11.222.333/0001-81", Document.format("11222333000181")
  end

  test "valor em reais vira centavos, com até duas casas (R5)" do
    assert_equal [ 123_456, nil ], Money.parse_cents("1.234,56")
    assert_equal [ 123_456, nil ], Money.parse_cents("1234,56")
    assert_equal [ 123_400, nil ], Money.parse_cents("1234")
    assert_equal [ 50, nil ], Money.parse_cents("0,5")
    assert_equal [ nil, "valor deve ser maior que zero" ], Money.parse_cents("0,00")
    assert_equal [ nil, "valor com mais de duas casas decimais" ], Money.parse_cents("12,345")
    assert_equal [ nil, "valor inválido" ], Money.parse_cents("abc")
    assert_equal [ nil, "valor obrigatório" ], Money.parse_cents("  ")
  end

  test "centavos viram texto brasileiro" do
    assert_equal "1.234,56", Money.format(123_456)
    assert_equal "0,05", Money.format(5)
    assert_equal "1.000.000,00", Money.format(100_000_000)
  end

  test "data dd/mm/aaaa, com dia e mês sem zero (R6)" do
    assert_equal Date.new(2026, 9, 1), BrDate.parse("1/9/2026")
    assert_equal Date.new(2026, 9, 10), BrDate.parse("10/09/2026")
    assert_nil BrDate.parse("31/02/2026")
    assert_nil BrDate.parse("2026-09-10")
  end

  test "comparação de nomes ignora maiúsculas, acentos e espaços (R7)" do
    assert_equal FoldedText.fold("MARIA  da Silva "), FoldedText.fold("Maria da Silva")
    assert_equal "jose conceicao", FoldedText.fold("  José   Conceição ")
  end
end
