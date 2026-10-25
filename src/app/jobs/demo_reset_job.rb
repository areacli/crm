# Recriação diária da demonstração pública (CRM_DEMO=1), às 4h de Brasília (config/initializers/demo.rb). Tolerante a falha: o erro fica no `TaskRun`
# e o job tenta de novo (cada tentativa apaga e recria do zero) em vez de deixar a demonstração pela metade.
class DemoResetJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 10.minutes, attempts: 3

  def perform = Demo::Reset.new.call
end
