require "csv"

module Agreements
  # Feriados estaduais e municipais que vêm com o sistema (11, R249, revisão 14): um arquivo de REGRAS, uma linha por feriado, com a norma que o institui e a
  # fonte em que foi lida. A regra é uma data fixa (`dd/mm`) ou móvel, contada da Páscoa (`pascoa+8`, `pascoa-3`), como os nacionais (`Charges::BusinessDays`).
  # A tabela `holidays` continua guardando datas: aqui elas são geradas, das regras, para os anos que o calendário da praça lê. Gerar de novo não duplica
  # nem apaga: o que o administrador importou (`CalendarImporter#holidays`) fica como está.
  module LocalHolidays
    BUNDLED = Rails.root.join("db/data/feriados-locais.csv")
    COLUMNS = %w[uf codigo_ibge regra nome norma fonte lido_em].freeze
    FIXED = %r{\A(\d{2})/(\d{2})\z}
    EASTER = /\Apascoa([+-]\d{1,3})\z/

    Rule = Data.define(:line, :state, :ibge_code, :rule, :name, :norm, :source, :read_on) do
      # A data desta regra no ano, ou nil quando ela não existe nele (29/02).
      def date_in(year)
        if (fixed = FIXED.match(rule))
          Date.valid_date?(year, fixed[2].to_i, fixed[1].to_i) ? Date.new(year, fixed[2].to_i, fixed[1].to_i) : nil
        elsif (easter = EASTER.match(rule))
          Charges::BusinessDays.easter(year) + easter[1].to_i
        end
      end

      # O que impede a regra de valer, ou nil: toda linha tem UF, regra legível, nome, norma e fonte (nada entra sem a norma lida).
      def problem
        return "UF inválida" unless Registry::Normalizer::UFS.include?(state)
        return "regra ilegível (#{rule})" unless FIXED.match?(rule) || EASTER.match?(rule)
        return "regra sem data (#{rule})" if FIXED.match?(rule) && date_in(2024).nil?
        return "falta o nome, a norma ou a fonte" if [ name, norm, source ].any?(&:blank?)

        nil
      end
    end

    Result = Data.define(:processed, :rejected)

    module_function

    def rules(path = BUNDLED)
      table = CSV.read(path, headers: true, col_sep: ";", encoding: "bom|utf-8")
      missing = COLUMNS - table.headers.map { |header| header.to_s.strip.downcase }
      raise ArgumentError, "colunas que faltam: #{missing.join(', ')}" if missing.any?

      table.each.with_index(2).map do |row, line|
        Rule.new(line: line, state: row["uf"].to_s.strip.upcase, ibge_code: row["codigo_ibge"].to_s.strip.presence, rule: row["regra"].to_s.strip.downcase,
                 name: row["nome"].to_s.squish, norm: row["norma"].to_s.squish, source: row["fonte"].to_s.strip, read_on: row["lido_em"].to_s.strip)
      end
    end

    # Os anos que o calendário da praça lê (`Square.calendar_for`: do ano passado a três à frente), com folga de dois: a geração anual os renova.
    def window(today = Date.current) = (today.year - 1)..(today.year + 5)

    # Gera as datas das regras nos anos pedidos e as grava em `holidays`, uma instrução por lote (consulta: o índice único de UF, município e data).
    # Linha com problema, ou de município fora da lista do IBGE, é recusada com o número dela, e o resto entra. Cada geração fica em `task_runs`.
    def generate(years: window, path: BUNDLED)
      municipalities = Municipality.pluck(:ibge_code, :id).to_h
      rejected = []
      rows = rules(path).flat_map do |rule|
        problem = rule.problem
        problem ||= "município #{rule.ibge_code} fora da lista do IBGE" if rule.ibge_code && !municipalities.key?(rule.ibge_code)
        next (rejected << "linha #{rule.line}: #{problem}") && [] if problem

        years.filter_map { |year| (date = rule.date_in(year)) && { state: rule.state, municipality_id: municipalities[rule.ibge_code], date: date, name: rule.name.first(150) } }
      end
      rows = rows.uniq { |row| row.values_at(:state, :municipality_id, :date) }
      Holiday.upsert_all(rows, unique_by: :index_holidays_on_state_and_municipality_id_and_date) if rows.any?
      TaskRun.create!(name: "generate_holidays", status: :succeeded, started_at: Time.current, finished_at: Time.current, processed: rows.size, failed: rejected.size,
                      note: rejected.first(3).join(" | ").first(300).presence)
      Result.new(rows.size, rejected)
    end
  end
end
