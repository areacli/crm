# Agendado às 5h30 (config/schedule.yml), depois da busca dos índices: um recálculo de segmentos por credor ativo (R153, MT-19).
class SegmentsDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true).find_each { |tenant| SegmentsRecalculationJob.perform_later(tenant) }
  end
end
