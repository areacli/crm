module Demo
  # A planilha de carteira fictícia da demonstração: a mesma função gera a carga inicial (todos os clientes) e o arquivo que substitui o do
  # visitante (alguns clientes que já existem, idênticos, e outros novos). Cada cliente tem de 1 a 4 títulos desde 2020, em todas as faixas
  # de atraso e a vencer, contratos próprios, alguns compartilhados com responsável financeiro, contatos e acréscimos já aplicados pelo credor.
  module PortfolioSheet
    HEADER = (Portfolio::CsvFile::REQUIRED + Portfolio::CsvFile::OPTIONAL).freeze
    FIRST_DUE = Date.new(2020, 1, 1)

    module_function

    def write(path, range, today: Date.current)
      File.open(path, "wb") do |file|
        file.write "#{HEADER.join(';')}\r\n"
        range.each { |seed| lines(seed, today).each { |cells| file.write "#{cells.join(';')}\r\n" } }
      end
      path
    end

    # Dias de atraso (negativo = a vencer) do título k do cliente: as faixas de 1 a 30, 31 a 60... e mais de 360 dias, e uma parte a vencer.
    def overdue_days(seed, k, today)
      roll = People.pick(seed, 20 + k) % 100
      span = People.pick(seed, 30 + k)
      case roll
      when 0...18 then -(1 + span % 45)
      when 18...60 then 1 + span % 90
      when 60...80 then 91 + span % 270
      when 80...93 then 361 + span % 540
      else 901 + span % [ (today - FIRST_DUE).to_i - 901, 1 ].max
      end
    end

    def lines(seed, today)
      count = 1 + People.pick(seed, 10) % 3
      count += 1 if People.pick(seed, 11) % 10 == 0
      split_contract = seed % 7 == 3
      shared = seed % 25 == 5 && seed.positive?
      (1..count).map do |k|
        due = today - overdue_days(seed, k, today)
        due = FIRST_DUE if due < FIRST_DUE
        cents = 4_500 + People.pick(seed, 40 + k) % 240_000
        contract = "CT-#{seed.to_s.rjust(7, '0')}#{'B' if split_contract && k.even?}"
        role = ""
        if shared && k == 1
          contract = "CT-#{(seed - 1).to_s.rjust(7, '0')}"
          role = "responsável financeiro"
        elsif k == 1 && seed % 25 == 4
          role = "titular"
        end
        cells = {
          "documento" => Document.format(People.document(seed)), "nome" => People.name(seed), "titulo" => "NF-#{seed}/#{k}", "vencimento" => due.strftime("%d/%m/%Y"),
          "valor" => Money.format(cents), "contrato" => contract, "descricao" => "#{People.product(seed, 50 + k)} de #{I18n.l(due, format: '%m/%Y')}",
          "papel" => role, "produto" => People.product(seed, 50 + k)
        }
        contacts(cells, seed) if k == 1
        surcharges(cells, cents, due, today, seed, k)
        HEADER.map { |column| cells[column].to_s }
      end
    end

    def contacts(cells, seed)
      cells["telefone"] = People.phone(seed) if People.pick(seed, 60) % 100 < 95
      cells["telefone2"] = People.phone(seed, 7) if People.pick(seed, 61) % 100 < 25
      cells["email"] = People.email(seed) if People.pick(seed, 62) % 100 < 80
      cells["email2"] = People.email(seed + 1_000_000) if People.pick(seed, 63) % 100 < 8
      return unless People.pick(seed, 64) % 100 < 40

      city, state, zip = People::CITIES[People.pick(seed, 65) % People::CITIES.size]
      cells.merge!("logradouro" => People::STREETS[People.pick(seed, 66) % People::STREETS.size], "numero" => (1 + People.pick(seed, 67) % 2000).to_s, "bairro" => "Centro",
                   "cidade" => city, "uf" => state, "cep" => zip)
    end

    # Acréscimos que o credor já aplicou em 4% dos títulos vencidos (R102): servem à comparação com o valor atualizado calculado pelo CRM.
    def surcharges(cells, cents, due, today, seed, k)
      return unless due < today - 30 && People.pick(seed, 70 + k) % 100 < 4

      cells["multa_credor"] = Money.format(cents * 2 / 100)
      cells["juros_credor"] = Money.format([ cents / 100 * ((today - due).to_i / 30), 1 ].max)
    end
  end
end
