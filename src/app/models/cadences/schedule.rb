module Cadences
  # A agenda da régua (21, R437): dias da semana, um horário de meia em meia hora (Brasília), a opção de não rodar em feriado nacional e a vigência.
  module Schedule
    module_function

    # A hora prevista do dia, ou nil quando a régua não roda nele.
    def slot(cadence, day)
      return nil unless cadence.valid_on?(day) && Array(cadence.schedule_days).include?(day.wday)
      return nil if cadence.skip_national_holidays && Charges::BusinessDays.national(day.year).include?(day)

      hour, minute = cadence.schedule_time.split(":").map(&:to_i)
      Time.zone.local(day.year, day.month, day.day, hour, minute)
    end

    # A próxima hora prevista a partir de agora (a conferência simula essa rodada, R442).
    def next_slot(cadence, from = Time.current)
      (0..400).each do |offset|
        slot = slot(cadence, from.to_date + offset)
        return slot if slot && slot >= from
      end
      nil
    end
  end
end
