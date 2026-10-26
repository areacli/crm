# Agendado a cada 5 minutos (config/schedule.yml): marca como "falhou" a importação sem avanço há mais de 30 minutos (01, importação presa).
class StaleImportsJob < ApplicationJob
  queue_as :default

  def perform = Portfolio::StaleImports.new.call
end
