require "prawn"

# O texto vai à fonte padrão já convertido para Windows-1252 (`safe`): o aviso do Prawn sobre fontes padrão e UTF-8 não se aplica.
Prawn::Fonts::AFM.hide_m17n_warning = true

module Payments
  # Ficha de compensação do boleto desenhada aqui, quando o fornecedor não devolve PDF (12, revisão 4, R284e; decisão 0034, Prawn). Peça genérica: o
  # adaptador entrega a linha digitável que o banco devolveu e os dados do título; a ficha reconstrói o código de barras da linha (`Febraban`), confere
  # os dígitos, o fator de vencimento e o valor contra o instrumento, e só então desenha. Se algo não fecha, levanta `Febraban::Invalid`: o instrumento
  # falha e nada vai ao cliente.
  #
  # Layout pelo manual do Bradesco (C l. 1837-1929): recibo do pagador em cima e ficha de compensação embaixo, separados por linha de corte; banco e
  # código com dígito à esquerda e linha digitável à direita na borda superior da ficha; código de barras intercalado 2 de 5 com módulo estreito de
  # 0,33 mm, largo de 3 vezes e 13 mm de altura, a 5 mm da borda esquerda. Fontes padrão do PDF (Helvetica), que só têm o Windows-1252: o texto fora
  # dele é trocado.
  class BoletoSlip
    MM = 72.0 / 25.4
    NARROW = 0.33 * MM
    BAR_HEIGHT = 13 * MM
    WIDE = 3

    # `free_field_check`: o adaptador confere o campo livre do banco dele (agência, carteira, nosso número, conta) contra a integração.
    def initialize(bank_name:, bank_code:, digitable_line:, due_on:, amount_cents:, beneficiary_name:, beneficiary_document:, agency_code:, wallet_our_number:,
                   document_number:, species:, issued_on:, payer_name:, payer_document:, payer_address:, payment_place:, instructions: [], free_field_check: nil)
      @slip = Febraban.parse_digitable(digitable_line)
      raise Febraban::Invalid, "o fator de vencimento da linha (#{@slip.due_factor}) não é o de #{due_on.strftime('%d/%m/%Y')}" unless @slip.due_factor == Febraban.due_factor(due_on)
      raise Febraban::Invalid, "o valor da linha não é o do título" unless @slip.amount_cents == amount_cents.to_i
      raise Febraban::Invalid, "o campo livre da linha não é o da integração" if free_field_check && !free_field_check.call(Febraban.bradesco_free_field(@slip.free_field))

      @line = Febraban.digitable_from_barcode(@slip.barcode)
      @values = { bank_name: bank_name, bank_code: bank_code, due_on: due_on, amount_cents: amount_cents, beneficiary_name: beneficiary_name,
                  beneficiary_document: beneficiary_document, agency_code: agency_code, wallet_our_number: wallet_our_number, document_number: document_number,
                  species: species, issued_on: issued_on, payer_name: payer_name, payer_document: payer_document, payer_address: payer_address,
                  payment_place: payment_place, instructions: instructions }
    end

    def barcode = @slip.barcode

    def digitable_line = @line

    # O PDF, em bytes. Sem compressão do conteúdo: o teste lê de volta as barras e o texto.
    def render
      document = Prawn::Document.new(page_size: "A4", margin: 10 * MM, compress: false, info: { Title: "Boleto #{@values[:document_number]}", Creator: "CRM" })
      width = document.bounds.width
      receipt(document, width)
      cut_line(document, width)
      compensation(document, width)
      document.render
    end

    private
      def receipt(document, width)
        document.font("Helvetica", size: 9) { document.text(safe("Recibo do pagador"), style: :bold) }
        document.move_down(2 * MM)
        header(document, width)
        grid(document, width, [
          [ [ "Beneficiário", "#{@values[:beneficiary_name]} - CNPJ #{document_label(@values[:beneficiary_document])}", 0.6 ], [ "Agência / Código do beneficiário", @values[:agency_code], 0.4 ] ],
          [ [ "Pagador", "#{@values[:payer_name]} - #{document_label(@values[:payer_document])}", 0.6 ], [ "Nosso número", @values[:wallet_our_number], 0.4 ] ],
          [ [ "Número do documento", @values[:document_number], 0.3 ], [ "Vencimento", date(@values[:due_on]), 0.3 ], [ "Valor do documento", money(@values[:amount_cents]), 0.4 ] ]
        ])
        document.move_down(4 * MM)
      end

      def cut_line(document, width)
        document.dash(3, space: 3)
        document.stroke_horizontal_line(0, width)
        document.undash
        document.move_down(1.5 * MM)
        document.font("Helvetica", size: 7) { document.text(safe("Corte na linha pontilhada"), align: :right) }
        document.move_down(4 * MM)
      end

      def compensation(document, width)
        header(document, width)
        grid(document, width, [
          [ [ "Local de pagamento", @values[:payment_place], 0.7 ], [ "Vencimento", date(@values[:due_on]), 0.3 ] ],
          [ [ "Beneficiário", "#{@values[:beneficiary_name]} - CNPJ #{document_label(@values[:beneficiary_document])}", 0.7 ], [ "Agência / Código do beneficiário", @values[:agency_code], 0.3 ] ],
          [ [ "Data do documento", date(@values[:issued_on]), 0.15 ], [ "Número do documento", @values[:document_number], 0.2 ], [ "Espécie doc.", @values[:species], 0.1 ],
            [ "Aceite", "N", 0.1 ], [ "Data do processamento", date(@values[:issued_on]), 0.15 ], [ "Carteira / Nosso número", @values[:wallet_our_number], 0.3 ] ],
          [ [ "Uso do banco", "", 0.15 ], [ "CIP", "000", 0.1 ], [ "Moeda", "R$", 0.1 ], [ "Quantidade", "", 0.15 ], [ "Valor", "", 0.2 ], [ "(=) Valor do documento", money(@values[:amount_cents]), 0.3 ] ]
        ])
        instructions(document, width)
        grid(document, width, [ [ [ "Pagador", "#{@values[:payer_name]} - #{document_label(@values[:payer_document])}\n#{@values[:payer_address]}", 1.0 ] ] ], height: 14 * MM)
        document.move_down(2 * MM)
        document.font("Helvetica", size: 7) { document.text(safe("Autenticação mecânica - Ficha de compensação"), align: :right) }
        document.move_down(2 * MM)
        bars(document)
      end

      # Banco e código à esquerda, linha digitável à direita, em cima de uma linha grossa.
      def header(document, width)
        top = document.cursor
        document.font("Helvetica", style: :bold, size: 12) do
          document.draw_text(safe(@values[:bank_name]), at: [ 0, top - 12 ])
          document.draw_text(@values[:bank_code], at: [ 30 * MM, top - 12 ])
        end
        document.font("Helvetica", style: :bold, size: 10.5) do
          document.text_box(@line, at: [ 48 * MM, top - 3 ], width: width - 48 * MM, height: 14, align: :right)
        end
        document.line_width = 1.5
        document.stroke_horizontal_line(0, width, at: top - 16)
        document.line_width = 0.5
        document.move_cursor_to(top - 16)
      end

      # Linhas de campos: [rótulo, valor, fração da largura].
      def grid(document, width, rows, height: 8.5 * MM)
        rows.each do |cells|
          top = document.cursor
          x = 0
          cells.each do |label, value, fraction|
            cell_width = width * fraction
            document.stroke_rectangle([ x, top ], cell_width, height)
            document.font("Helvetica", size: 6) { document.draw_text(safe(label), at: [ x + 1.5, top - 7 ]) }
            document.font("Helvetica", size: 8.5) do
              document.text_box(safe(value.to_s), at: [ x + 1.5, top - 9 ], width: cell_width - 3, height: height - 9, overflow: :shrink_to_fit, min_font_size: 6)
            end
            x += cell_width
          end
          document.move_cursor_to(top - height)
        end
      end

      def instructions(document, width)
        top = document.cursor
        height = 20 * MM
        document.stroke_rectangle([ 0, top ], width, height)
        document.font("Helvetica", size: 6) { document.draw_text(safe("Instruções (texto de responsabilidade do beneficiário)"), at: [ 1.5, top - 7 ]) }
        document.font("Helvetica", size: 8.5) do
          document.text_box(safe(@values[:instructions].join("\n")), at: [ 1.5, top - 9 ], width: width - 3, height: height - 10, overflow: :shrink_to_fit, min_font_size: 6)
        end
        document.move_cursor_to(top - height)
      end

      # O código de barras, 5 mm da borda esquerda (a margem da página já é 10 mm; o desenho começa no limite dela).
      def bars(document)
        top = document.cursor
        x = 0
        Febraban.itf_bars(@slip.barcode, wide: WIDE).each do |modules, bar|
          width = modules * NARROW
          document.fill_rectangle([ x, top ], width, BAR_HEIGHT) if bar
          x += width
        end
        document.move_cursor_to(top - BAR_HEIGHT)
      end

      def date(value) = value&.strftime("%d/%m/%Y").to_s

      def money(cents)
        reais, centavos = cents.to_i.divmod(100)
        "R$ #{reais.to_s.reverse.scan(/\d{1,3}/).join('.').reverse},#{centavos.to_s.rjust(2, '0')}"
      end

      def document_label(number)
        digits = number.to_s.gsub(/\D/, "")
        case digits.length
        when 14 then "#{digits[0, 2]}.#{digits[2, 3]}.#{digits[5, 3]}/#{digits[8, 4]}-#{digits[12, 2]}"
        when 11 then "#{digits[0, 3]}.#{digits[3, 3]}.#{digits[6, 3]}-#{digits[9, 2]}"
        else digits
        end
      end

      # O que a Helvetica padrão (Windows-1252) não tem vira "?": o boleto nunca deixa de sair por um caractere.
      def safe(text) = text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end
end
