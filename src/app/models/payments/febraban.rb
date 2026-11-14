module Payments
  # Regras do boleto da FEBRABAN que a ficha de compensação gerada aqui precisa (12, revisão 4, R284e), sem rede nem biblioteca: a linha digitável de
  # 47 dígitos em cinco campos, o código de barras de 44 posições reconstruído dela, os dígitos verificadores (módulo 10 em cada campo da linha, módulo 11
  # no geral), o fator de vencimento (que recomeçou em 1000 em 22/02/2025) e as barras do intercalado 2 de 5. A especificação técnica da FEBRABAN não
  # está entre os documentos guardados: as regras são as do layout público e são conferidas, por teste, contra o exemplo do manual do Bradesco (linha
  # da C l. 1455, vencimento 21/09/2025 com fator 1211). Nada aqui confia na linha recebida: o que não fecha levanta `Invalid`.
  module Febraban
    class Invalid < StandardError; end

    # Linha conferida: os 44 dígitos do código de barras e o que eles dizem.
    Slip = Data.define(:barcode, :bank, :currency, :due_factor, :amount_cents, :free_field)
    # Campo livre do Bradesco (C l. 1795-1806): agência (4), carteira (2), nosso número (11), conta (7) e zero (1).
    BradescoFreeField = Data.define(:agency, :wallet, :our_number, :account)

    FACTOR_BASE = Date.new(1997, 10, 7)

    module_function

    # Lê a linha digitável e confere os quatro dígitos: o de cada um dos três primeiros campos e o geral, do código de barras.
    def parse_digitable(line)
      digits = line.to_s.gsub(/\D/, "")
      raise Invalid, "a linha digitável tem #{digits.length} dígitos, não 47" unless digits.length == 47

      fields = [ [ digits[0, 9], digits[9] ], [ digits[10, 10], digits[20] ], [ digits[21, 10], digits[31] ] ]
      fields.each_with_index do |(body, check), index|
        raise Invalid, "o dígito do campo #{index + 1} da linha digitável não confere" unless mod10(body).to_s == check
      end
      barcode = digits[0, 4] + digits[32] + digits[33, 14] + digits[4, 5] + digits[10, 10] + digits[21, 10]
      raise Invalid, "o dígito geral do código de barras não confere" unless barcode_check_digit(barcode[0, 4] + barcode[5, 39]).to_s == barcode[4]

      Slip.new(barcode: barcode, bank: barcode[0, 3], currency: barcode[3], due_factor: barcode[5, 4].to_i, amount_cents: barcode[9, 10].to_i, free_field: barcode[19, 25])
    end

    # Linha digitável formatada a partir do código de barras (para conferir o que o banco mandou e para imprimir).
    def digitable_from_barcode(barcode)
      raise Invalid, "o código de barras tem #{barcode.to_s.length} dígitos, não 44" unless barcode.to_s.match?(/\A\d{44}\z/)

      free = barcode[19, 25]
      first = barcode[0, 4] + free[0, 5]
      second = free[5, 10]
      third = free[15, 10]
      "#{first[0, 5]}.#{first[5, 4]}#{mod10(first)} #{second[0, 5]}.#{second[5, 5]}#{mod10(second)} #{third[0, 5]}.#{third[5, 5]}#{mod10(third)} #{barcode[4]} #{barcode[5, 14]}"
    end

    # Módulo 10 com pesos 2 e 1 da direita para a esquerda, somando os algarismos de cada produto.
    def mod10(number)
      sum = number.to_s.reverse.chars.each_with_index.sum do |char, index|
        product = char.to_i * (index.even? ? 2 : 1)
        product > 9 ? product - 9 : product
      end
      (10 - sum % 10) % 10
    end

    # Dígito geral do código de barras: módulo 11 com pesos 2 a 9 sobre as 43 posições sem o dígito; 0, 10 e 11 viram 1.
    def barcode_check_digit(number43)
      digit = 11 - weighted_mod11(number43, 9)
      digit.in?([ 0, 10, 11 ]) ? 1 : digit
    end

    # Dígito do nosso número do Bradesco: módulo 11 com pesos 2 a 7 sobre carteira (2) e nosso número (11); resto 1 dá "P", resto 0 dá "0". O manual
    # não traz a regra, mas os quatro exemplos da lista de liquidados (C l. 4073-4140, carteira 09) conferem com ela; a homologação confere num boleto real.
    def bradesco_our_number_digit(wallet, our_number)
      rest = weighted_mod11(wallet.to_s.rjust(2, "0") + our_number.to_s.rjust(11, "0"), 7) % 11
      case rest
      when 0 then "0"
      when 1 then "P"
      else (11 - rest).to_s
      end
    end

    # Fator de vencimento: dias desde 07/10/1997, de 1000 a 9999; depois de 9999 (21/02/2025) recomeça em 1000 (22/02/2025).
    def due_factor(date) = ((date - FACTOR_BASE).to_i - 1000) % 9000 + 1000

    def bradesco_free_field(free)
      raise Invalid, "campo livre do Bradesco sem o zero final" unless free.to_s.length == 25 && free[24] == "0"

      BradescoFreeField.new(agency: free[0, 4], wallet: free[4, 2], our_number: free[6, 11], account: free[17, 7])
    end

    # Barras do intercalado 2 de 5 (44 dígitos, em pares: o primeiro algarismo nas barras, o segundo nos espaços), com o início (estreito, estreito,
    # estreito, estreito) e o fim (larga, estreito, estreito). Devolve [[largura em módulos, barra?], ...]: estreita = 1, larga = 3.
    ITF_PATTERNS = %w[00110 10001 01001 11000 00101 10100 01100 00011 10010 01010].freeze

    def itf_bars(code, wide: 3)
      raise Invalid, "o intercalado 2 de 5 pede quantidade par de dígitos" unless code.to_s.match?(/\A(\d\d)+\z/)

      elements = [ [ 1, true ], [ 1, false ], [ 1, true ], [ 1, false ] ]
      code.chars.each_slice(2) do |bar_digit, space_digit|
        ITF_PATTERNS[bar_digit.to_i].chars.zip(ITF_PATTERNS[space_digit.to_i].chars).each do |bar, space|
          elements << [ bar == "1" ? wide : 1, true ] << [ space == "1" ? wide : 1, false ]
        end
      end
      elements << [ wide, true ] << [ 1, false ] << [ 1, true ]
    end

    # Lê de volta as barras (só as larguras das barras, em sequência) e devolve os dígitos: serve ao teste que confere o desenho do PDF.
    def itf_decode(bar_widths, space_widths)
      bars = bar_widths[2...-2]
      spaces = space_widths[2...-1]
      raise Invalid, "barras em quantidade inesperada" unless bars.size % 5 == 0 && bars.size == spaces.size

      narrow = (bar_widths + space_widths).min
      flag = ->(width) { width > narrow * 1.5 ? "1" : "0" }
      bars.each_slice(5).zip(spaces.each_slice(5)).map do |bar_group, space_group|
        [ ITF_PATTERNS.index(bar_group.map(&flag).join), ITF_PATTERNS.index(space_group.map(&flag).join) ].join
      end.join
    end

    def weighted_mod11(number, max_weight)
      number.to_s.reverse.chars.each_with_index.sum { |char, index| char.to_i * (2 + index % (max_weight - 1)) } % 11
    end
  end
end
