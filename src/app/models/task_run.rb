# Execução de uma tarefa agendada (O8): de um credor ou global, com quando rodou, quantos processou e o resultado. A falha guarda só o tipo
# do erro; o detalhe, que pode ter dado da linha, vai para o registro da aplicação (revisão geral, D5).
class TaskRun < ApplicationRecord
  belongs_to :tenant, optional: true

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed", skipped: "skipped" }, validate: true

  scope :recent, -> { order(started_at: :desc, id: :desc) }
end
