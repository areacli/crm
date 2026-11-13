# Geração anual das datas dos feriados estaduais e das capitais, das regras que vêm com o sistema (11, R249, revisão 14; O8): global, em 2 de janeiro.
# O calendário da praça lê até três anos à frente e a geração cobre cinco, então um ano sem rodar não deixa buraco. Registra em `task_runs`.
class GenerateHolidaysJob < ApplicationJob
  queue_as :default

  def perform = Agreements::LocalHolidays.generate
end
