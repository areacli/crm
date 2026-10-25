# Datas no formato dd/mm/aaaa, com dia e mês sem zero à esquerda aceitos (R6).
module BrDate
  module_function

  def parse(raw)
    match = raw.to_s.strip.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z})
    return unless match

    day, month, year = match.captures.map(&:to_i)
    Date.valid_date?(year, month, day) ? Date.new(year, month, day) : nil
  end

  # O nome da zona da aplicação no banco (Brasília): `timestamptz` é gravado em UTC, e `coluna::date` usaria a data de lá. Depois das 21h de Brasília a data de UTC já é a do dia
  # seguinte, e a conta de idade, de última movimentação e de guarda contaria um dia a menos. Toda conversão de instante em data, no SQL, passa por `sql_date`.
  def zone_name = Time.zone.tzinfo.name

  # A data (de Brasília) de uma coluna de instante, para usar dentro de uma consulta: `(coluna at time zone 'America/Sao_Paulo')::date`.
  def sql_date(column) = "(#{column} at time zone '#{zone_name}')::date"
end
