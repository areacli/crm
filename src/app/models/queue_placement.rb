# Onde um sujeito (cliente ou contrato) está no enquadramento da fila (15, R349 a R351, R355, R356): a fila (nula = sem fila), a posição
# calculada no recálculo e quando volta a ficar disponível depois de um acionamento ou até a hora do retorno.
class QueuePlacement < ApplicationRecord
  include TenantScoped

  belongs_to :work_queue, optional: true
end
