require "test_helper"
require "csv"

# Feriados estaduais e municipais que vêm com o sistema (11, R249, revisão 14): o arquivo de regras, a geração das datas e o efeito no calendário da praça.
class Agreements::LocalHolidaysTest < ActiveSupport::TestCase
  # A lista do IBGE entra de uma vez: a importação do administrador grava linha a linha e levaria minutos em cada teste.
  setup do
    rows = CSV.read(Municipality::BUNDLED, headers: true, col_sep: ";", encoding: "bom|utf-8").map do |row|
      { ibge_code: row["codigo_ibge"], name: row["nome"], state: row["uf"], name_key: FoldedText.fold(row["nome"]) }
    end
    Municipality.insert_all!(rows)
  end

  def rules_file(lines)
    path = Rails.root.join("tmp", "feriados-#{SecureRandom.hex(4)}.csv").to_s
    File.write(path, ([ Agreements::LocalHolidays::COLUMNS.join(";") ] + lines).join("\n"))
    path
  end

  test "o arquivo que vem com o sistema é legível: toda linha tem UF, regra, nome, norma, fonte e, quando municipal, um município da lista do IBGE na mesma UF" do
    rules = Agreements::LocalHolidays.rules
    assert_operator rules.size, :>=, 14
    assert_empty rules.filter_map { |rule| "linha #{rule.line}: #{rule.problem}" if rule.problem }
    assert_empty rules.reject { |rule| rule.source.start_with?("http") && Date.iso8601(rule.read_on) }.map(&:line), "fonte e data da leitura"
    states = Municipality.where(ibge_code: rules.filter_map(&:ibge_code)).pluck(:ibge_code, :state).to_h
    assert_empty rules.select(&:ibge_code).reject { |rule| states[rule.ibge_code] == rule.state }.map(&:line), "município da lista, na UF da linha"
    assert_equal rules.size, rules.uniq { |rule| [ rule.state, rule.ibge_code, rule.rule ] }.size, "sem regra repetida"
  end

  test "a geração grava as datas dos anos pedidos, não duplica ao repetir e não mexe no que o administrador importou" do
    campinas = Municipality.find_by!(ibge_code: "3509502")
    imported = Holiday.create!(state: "SP", municipality: campinas, date: Date.new(2027, 7, 14), name: "Importado pelo administrador")

    result = Agreements::LocalHolidays.generate(years: 2026..2028)
    assert_empty result.rejected
    assert_equal Agreements::LocalHolidays.rules.size * 3, result.processed
    assert_equal [ Date.new(2026, 7, 9), Date.new(2027, 7, 9), Date.new(2028, 7, 9) ], Holiday.where(state: "SP", municipality_id: nil).order(:date).pluck(:date)
    assert_equal "Dia do Evangélico", Holiday.find_by!(municipality: campinas, date: Date.new(2027, 8, 12)).name
    run = TaskRun.where(name: "generate_holidays").sole
    assert_equal [ "succeeded", result.processed, 0 ], [ run.status, run.processed, run.failed ]

    assert_no_difference -> { Holiday.count } do
      Agreements::LocalHolidays.generate(years: 2026..2028)
    end
    assert_equal "Importado pelo administrador", imported.reload.name
  end

  test "a regra é data fixa ou contada da Páscoa; linha ilegível, sem norma ou de município fora da lista é recusada com o número dela, e o resto entra" do
    path = rules_file([ "ES;;pascoa+8;Nossa Senhora da Penha;Lei de exemplo 1/2000;https://exemplo.gov.br/lei;2026-11-13",
                        "ES;;29/02;Dia bissexto;Lei de exemplo 2/2000;https://exemplo.gov.br/lei;2026-11-13",
                        "ES;;31/02;Dia que não existe;Lei de exemplo 3/2000;https://exemplo.gov.br/lei;2026-11-13",
                        "ES;;terceira segunda de maio;Regra que o sistema não lê;Lei de exemplo 4/2000;https://exemplo.gov.br/lei;2026-11-13",
                        "ES;9999999;10/10;Município que não existe;Lei de exemplo 5/2000;https://exemplo.gov.br/lei;2026-11-13",
                        "ES;;11/11;Sem norma;;https://exemplo.gov.br/lei;2026-11-13",
                        "XX;;12/12;UF que não existe;Lei de exemplo 6/2000;https://exemplo.gov.br/lei;2026-11-13" ])

    result = Agreements::LocalHolidays.generate(years: 2027..2028, path: path)

    # Páscoa de 2027: 28/03; de 2028: 16/04. O 29/02 só existe em 2028.
    assert_equal [ Date.new(2027, 4, 5), Date.new(2028, 2, 29), Date.new(2028, 4, 24) ], Holiday.where(state: "ES").order(:date).pluck(:date)
    assert_equal [ "linha 4: regra sem data (31/02)", "linha 5: regra ilegível (terceira segunda de maio)", "linha 6: município 9999999 fora da lista do IBGE",
                   "linha 7: falta o nome, a norma ou a fonte", "linha 8: UF inválida" ], result.rejected
    assert_equal 5, TaskRun.where(name: "generate_holidays").sole.failed
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "com os feriados gerados, a praça muda o vencimento: 25/01 em São Paulo e 08/12 em Campinas, e não no Rio" do
    Agreements::LocalHolidays.generate(years: 2027..2027)
    calendar = ->(code) { Agreements::Calendar.for(Municipality.find_by!(ibge_code: code), years: 2027..2027) }

    assert_equal Date.new(2027, 1, 26), calendar.call("3550308").next_business(Date.new(2027, 1, 25))
    assert_equal Date.new(2027, 12, 9), calendar.call("3509502").next_business(Date.new(2027, 12, 8))
    assert_not calendar.call("3509502").business?(Date.new(2027, 7, 9)), "o estadual vale para todo município de SP"
    assert calendar.call("3304557").business?(Date.new(2027, 1, 25))
    assert_not calendar.call("3304557").business?(Date.new(2027, 4, 23)), "São Jorge, estadual do Rio"
  end

  test "os dados de referência carregam sem comando do administrador: municípios só com a tabela vazia, feriados sempre, sem duplicar" do
    assert_no_difference -> { Municipality.count } do
      Agreements::ReferenceData.load
    end
    assert_operator Holiday.count, :>=, 14 * Agreements::LocalHolidays.window.size
    assert_no_difference -> { Holiday.count } do
      GenerateHolidaysJob.perform_now
    end
    assert_equal 2, TaskRun.where(name: "generate_holidays", status: "succeeded").count
    assert_equal "GenerateHolidaysJob", YAML.load_file(Rails.root.join("config/schedule.yml")).dig("generate_holidays", "class")
  end
end
