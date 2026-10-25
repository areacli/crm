require "csv"

module Agreements
  # Importação das tabelas do administrador (11, R249, O8): municípios do IBGE (`codigo_ibge;nome;uf`) e feriados estaduais e municipais
  # (`uf;codigo_ibge;data;nome`, com o código vazio no feriado estadual). Repetir a importação não duplica: cada linha atualiza a existente. Cada
  # importação fica registrada em `task_runs`. Linha inválida é recusada com o número dela e o resto entra.
  class CalendarImporter
    Result = Data.define(:processed, :rejected)

    def municipalities(path)
      count = 0
      rejected = []
      each_row(path, %w[codigo_ibge nome uf]) do |line, row|
        municipality = Municipality.find_or_initialize_by(ibge_code: row["codigo_ibge"].to_s.strip)
        municipality.assign_attributes(name: row["nome"].to_s.squish, state: row["uf"].to_s.strip.upcase)
        municipality.save ? count += 1 : rejected << "linha #{line}: #{municipality.errors.full_messages.to_sentence}"
      end
      register("import_municipalities", count, rejected)
    end

    def holidays(path)
      count = 0
      rejected = []
      each_row(path, %w[uf codigo_ibge data nome]) do |line, row|
        date = BrDate.parse(row["data"]) || (Date.iso8601(row["data"].to_s) rescue nil)
        municipality = Municipality.find_by(ibge_code: row["codigo_ibge"].to_s.strip) if row["codigo_ibge"].to_s.strip.present?
        if row["codigo_ibge"].to_s.strip.present? && municipality.nil?
          rejected << "linha #{line}: município #{row['codigo_ibge']} fora da lista do IBGE"
          next
        end
        state = row["uf"].to_s.strip.upcase
        holiday = Holiday.find_or_initialize_by(state: state, municipality_id: municipality&.id, date: date)
        holiday.name = row["nome"].to_s.squish
        holiday.save ? count += 1 : rejected << "linha #{line}: #{holiday.errors.full_messages.to_sentence}"
      end
      register("import_holidays", count, rejected)
    end

    private
      def each_row(path, columns)
        table = CSV.read(path, headers: true, col_sep: ";", encoding: "bom|utf-8")
        missing = columns - table.headers.map { |header| header.to_s.strip.downcase }
        raise ArgumentError, "colunas que faltam: #{missing.join(', ')}" if missing.any?

        table.each.with_index(2) { |row, line| yield line, row.to_h.transform_keys { |key| key.to_s.strip.downcase } }
      end

      def register(name, count, rejected)
        TaskRun.create!(name: name, status: :succeeded, started_at: Time.current, finished_at: Time.current, processed: count, failed: rejected.size, note: rejected.first(3).join(" | ").first(300).presence)
        Result.new(count, rejected)
      end
  end
end
