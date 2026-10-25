module Portfolio
  # Valida uma linha da planilha contra as regras de identificação e validação (R1 a R6) e os limites de tamanho de campo.
  # Devolve [linha normalizada, nil] ou [nil, motivo da recusa].
  class RowValidator
    # Limites de caracteres por campo (especificação 01, formato da planilha).
    LIMITS = { "nome" => 300, "titulo" => 100, "contrato" => 100, "descricao" => 300, "email" => 254, "telefone" => 60, "produto" => 100,
               **Registry::LoadContacts::PHONES.drop(1).index_with { 60 }, **Registry::LoadContacts::EMAILS.drop(1).index_with { 254 } }.freeze
    FIELD_NAMES = { "documento" => "documento", "nome" => "nome", "titulo" => "título", "vencimento" => "vencimento", "valor" => "valor",
                    "telefone" => "telefone", "email" => "e-mail", "contrato" => "contrato", "descricao" => "descrição", "papel" => "papel", "produto" => "produto" }.freeze
    # Colunas de acréscimos já aplicados pelo credor (R102), na ordem de ParsedRow.
    SURCHARGES = %w[multa_credor juros_credor correcao_credor outros_credor].freeze
    ROLES = { "titular" => "holder", "responsavelfinanceiro" => "financial_responsible", "responsavel" => "financial_responsible" }.freeze

    def validate(csv_row)
      values = csv_row.values
      return [ nil, "linha com mais colunas que o cabeçalho" ] if csv_row.extra
      return [ nil, "linha incompleta" ] if csv_row.short

      CsvFile::REQUIRED.each { |field| return [ nil, "#{FIELD_NAMES[field]} obrigatório" ] if values[field].blank? }
      problem = Document.problem(values["documento"])
      return [ nil, problem ] if problem

      LIMITS.each do |field, max|
        return [ nil, "#{FIELD_NAMES.fetch(field, field)} acima de #{max} caracteres" ] if values[field].to_s.length > max
      end
      # 10, R187a: o número da promessa chega no lugar do número do título; um título não pode ter o formato dele.
      return [ nil, "título no formato de número de promessa (PRM-)" ] if Promises.number?(values["titulo"])

      due = BrDate.parse(values["vencimento"])
      return [ nil, "data inválida" ] unless due

      cents, money_problem = Money.parse_cents(values["valor"])
      return [ nil, money_problem ] unless cents

      roles, role_problem = parse_roles(values["papel"].to_s)
      return [ nil, role_problem ] if role_problem

      surcharges = SURCHARGES.map do |column|
        extra = parse_surcharge(values[column])
        return [ nil, "#{column} inválido" ] if extra == :invalid

        extra
      end

      contacts, warnings = Registry::LoadContacts.parse(values)
      [ ParsedRow.new(line: csv_row.line, document: Document.normalize(values["documento"]), name: values["nome"], contacts: contacts, warnings: warnings, contract: values["contrato"].presence, number: values["titulo"], due_date: due,
                      amount_cents: cents, description: values["descricao"].presence, roles: roles, product: values["produto"].presence,
                      penalty_cents: surcharges[0], interest_cents: surcharges[1], correction_cents: surcharges[2], other_cents: surcharges[3]), nil ]
    end

    private
      # Acréscimo do credor (R102): vazio é nulo; aceita zero; valor inválido ou negativo recusa a linha (R103).
      def parse_surcharge(raw)
        return nil if raw.to_s.strip.empty?

        value = raw.to_s.strip
        match = value.match(/\A(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\z/)
        return :invalid unless match

        match[1].delete(".").to_i * 100 + match[2].to_s.ljust(2, "0").to_i
      end

      # Papéis do cliente no contrato (R9b): "titular", "responsável financeiro" ou os dois separados por barra, sem diferenciar
      # maiúsculas nem acentos. Vazio não declara papel (vale os dois). Valor desconhecido recusa a linha.
      def parse_roles(raw)
        return [ nil, nil ] if raw.strip.empty?

        roles = raw.split("/").map do |token|
          role = ROLES[FoldedText.fold(token).delete(" ")]
          return [ nil, "papel inválido: #{token.strip}" ] unless role

          role
        end
        [ roles.uniq.sort.join(","), nil ]
      end
  end
end
