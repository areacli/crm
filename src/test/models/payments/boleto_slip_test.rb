require "test_helper"

# Ficha de compensação gerada aqui (12, revisão 4, R284e; decisão 0034): as regras da FEBRABAN conferidas contra o exemplo do manual do Bradesco e o
# código de barras lido de volta do PDF desenhado. Nenhuma rede.
class PaymentsBoletoSlipTest < ActiveSupport::TestCase
  # Exemplo do registro no manual de cobrança (C l. 1455): agência 2856, carteira 09, nosso número 52280000492, conta 0222652, R$ 1.255,99, 21/09/2025.
  LINE = "23792.85600 95228.000048 92022.265208 2 12110000125599".freeze
  BARCODE = "23792121100001255992856095228000049202226520".freeze

  def slip(line: LINE, due_on: Date.new(2025, 9, 21), amount_cents: 125_599, free_field_check: nil)
    Payments::BoletoSlip.new(bank_name: "Bradesco", bank_code: "237-2", digitable_line: line, due_on: due_on, amount_cents: amount_cents, beneficiary_name: "Escola Alfa Ltda",
                             beneficiary_document: "41755489000155", agency_code: "2856-1/0222652-7", wallet_our_number: "09 / 52280000492-5", document_number: "CRM00000000001",
                             species: "ME", issued_on: Date.new(2025, 8, 18), payer_name: "João José da Silva", payer_document: "11438390807",
                             payer_address: "Avenida Copacabana, 237 | Alphaville - Barueri - SP | 06050040", payment_place: "Pagável preferencialmente na rede Bradesco",
                             instructions: [ "Após o vencimento, multa de 2,00%." ], free_field_check: free_field_check)
  end

  test "a linha do manual fecha: dígitos dos campos, dígito geral, fator 1211 de 21/09/2025, valor e campo livre (R284e)" do
    parsed = Payments::Febraban.parse_digitable(LINE)
    assert_equal BARCODE, parsed.barcode
    assert_equal [ "237", "9", 1211, 125_599 ], [ parsed.bank, parsed.currency, parsed.due_factor, parsed.amount_cents ]
    free = Payments::Febraban.bradesco_free_field(parsed.free_field)
    assert_equal [ "2856", "09", "52280000492", "0222652" ], [ free.agency, free.wallet, free.our_number, free.account ]
    assert_equal LINE, Payments::Febraban.digitable_from_barcode(BARCODE)
  end

  test "fator de vencimento: 9999 em 21/02/2025 e recomeço em 1000 no dia seguinte" do
    assert_equal 9999, Payments::Febraban.due_factor(Date.new(2025, 2, 21))
    assert_equal 1000, Payments::Febraban.due_factor(Date.new(2025, 2, 22))
    assert_equal 1211, Payments::Febraban.due_factor(Date.new(2025, 9, 21))
  end

  test "dígito do nosso número do Bradesco confere com os exemplos da lista de liquidados (C l. 4073-4140)" do
    { "17080004198" => "3", "17124005842" => "3", "17124005843" => "1", "17075004058" => "1" }.each do |number, digit|
      assert_equal digit, Payments::Febraban.bradesco_our_number_digit("09", number), number
    end
  end

  test "qualquer dígito trocado na linha é recusado, e nada é desenhado (R284e)" do
    digits = LINE.gsub(/\D/, "")
    [ 3, 12, 25, 32, 40 ].each do |position|
      changed = digits.dup
      changed[position] = ((changed[position].to_i + 1) % 10).to_s
      assert_raises(Payments::Febraban::Invalid, "posição #{position}") { slip(line: changed) }
    end
    assert_raises(Payments::Febraban::Invalid) { slip(line: digits[0, 46]) }
  end

  test "vencimento, valor ou campo livre diferentes do instrumento recusam a ficha (R284e)" do
    assert_raises(Payments::Febraban::Invalid) { slip(due_on: Date.new(2025, 9, 22)) }
    assert_raises(Payments::Febraban::Invalid) { slip(amount_cents: 125_598) }
    assert_raises(Payments::Febraban::Invalid) { slip(free_field_check: ->(free) { free.our_number == "52280000493" }) }
    assert_equal BARCODE, slip(free_field_check: ->(free) { free.our_number == "52280000492" }).barcode
  end

  test "o PDF tem a linha digitável, os dados do título e o código de barras que se lê de volta igual (R284e, R273)" do
    pdf = slip.render
    assert pdf.start_with?("%PDF")
    text = text_from(pdf)
    assert_includes text, LINE
    [ "21/09/2025", "R$ 1.255,99", "09 / 52280000492-5", "2856-1/0222652-7", "41.755.489/0001-55", "Escola Alfa Ltda", "Após o vencimento, multa de 2,00%." ].each { |value| assert_includes text, value, value }
    assert_includes text, "João José da Silva", "o acento sai pela codificação da fonte padrão (Windows-1252)"
    assert_equal BARCODE, bars_from(pdf)
  end

  private
    # O texto de cada operação de texto (TJ), em hexadecimal na codificação Windows-1252, juntando os pedaços que o ajuste de espaçamento separa.
    def text_from(pdf)
      pdf.b.scan(/\[(.*?)\] TJ/m).map { |(array)| [ array.scan(/<(\h*)>/).join ].pack("H*").force_encoding("Windows-1252").encode("UTF-8") }.join("\n")
    end

    # Lê os retângulos preenchidos da última faixa (as barras) no conteúdo sem compressão: "x y largura altura re" seguidos de "f".
    def bars_from(pdf)
      rectangles = pdf.b.scan(/(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+) re\s+f/).map { |values| values.map(&:to_f) }
      height = Payments::BoletoSlip::BAR_HEIGHT
      bars = rectangles.select { |_x, _y, _width, h| (h - height).abs < 0.01 }.sort_by(&:first)
      widths = bars.map { |_x, _y, width, _h| width }
      gaps = bars.each_cons(2).map { |(x1, _, w1, _), (x2, _, _, _)| (x2 - x1 - w1).round(3) }
      Payments::Febraban.itf_decode(widths, gaps)
    end
end
