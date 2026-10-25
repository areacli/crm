# Datas no formato dd/mm/aaaa, com dia e mês sem zero à esquerda aceitos (R6).
module BrDate
  module_function

  def parse(raw)
    match = raw.to_s.strip.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z})
    return unless match

    day, month, year = match.captures.map(&:to_i)
    Date.valid_date?(year, month, day) ? Date.new(year, month, day) : nil
  end
end
