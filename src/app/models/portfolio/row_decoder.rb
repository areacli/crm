module Portfolio
  # Converte o texto de um registro da carteira nos tipos do registro canônico (decisão 0031): data, centavos, papéis, acréscimos e contatos. Só conhece
  # formato e nunca recusa: o que não pôde ser convertido fica em `format_problems`, e o validador decide, na ordem das regras. `raw` guarda o texto como
  # chegou, porque os limites de tamanho e a chave da R15 leem o texto.
  class RowDecoder
    Record = Data.define(:position, :extra, :short, :raw, :document, :due_date, :amount_cents, :roles, :surcharges, :contacts, :warnings, :format_problems)

    # Colunas de acréscimos já aplicados pelo credor (R102), na ordem de ParsedRow.
    SURCHARGES = %w[multa_credor juros_credor correcao_credor outros_credor].freeze
    ROLES = { "titular" => "holder", "responsavelfinanceiro" => "financial_responsible", "responsavel" => "financial_responsible" }.freeze

    def decode(raw)
      values = raw.values
      problems = {}
      due_date = BrDate.parse(values["vencimento"])
      problems[:due_date] = "data inválida" unless due_date
      cents, money_problem = Money.parse_cents(values["valor"])
      problems[:amount] = money_problem if money_problem
      roles, role_problem = parse_roles(values["papel"].to_s)
      problems[:roles] = role_problem if role_problem
      surcharges = SURCHARGES.map do |column|
        extra = parse_surcharge(values[column])
        problems[:surcharges] ||= "#{column} inválido" if extra == :invalid
        extra
      end
      contacts, warnings = Registry::LoadContacts.parse(values)
      Record.new(position: raw.position, extra: raw.extra, short: raw.short, raw: values, document: Document.normalize(values["documento"]), due_date: due_date,
                 amount_cents: cents, roles: roles, surcharges: surcharges, contacts: contacts, warnings: warnings, format_problems: problems)
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
