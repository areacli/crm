# Textos curtos das filas (15).
module QueuesHelper
  # 240 → "4 h"; 4320 → "3 dias"; 90 → "1,5 h".
  def duracao_curta(minutes)
    return "na hora" if minutes.zero?
    return "#{number_br(minutes / 1440)} #{minutes / 1440 == 1 ? 'dia' : 'dias'}" if (minutes % 1440).zero?

    "#{horas(minutes)} h"
  end

  def horas(minutes) = (minutes / 60.0).to_s.delete_suffix(".0").tr(".", ",")
end
