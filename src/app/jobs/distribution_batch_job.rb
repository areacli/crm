# Conferência e confirmação do lote de distribuição em segundo plano (14, R316), com o aviso pelo WebSocket quando termina e no sino de quem pediu.
class DistributionBatchJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(batch, step)
    step == "confirm" ? Distributions::BatchConfirmer.new(batch).call : Distributions::BatchChecker.new(batch).call
    notify(batch, step)
  rescue StandardError
    batch.update!(status: "failed") unless batch.reload.confirmed?
    notify(batch, step)
    raise
  ensure
    DistributionsChannel.broadcast_to(batch.tenant, { event: "distribution-batch-ready" })
  end

  private
    def notify(batch, step)
      what = I18n.t("distribution_batches.steps.#{step}")
      where = I18n.t("distribution_batches.where", name: batch.operation.short_name)
      return BackgroundNotice.finished(batch.user, what: what, where: where) unless batch.failed?

      BackgroundNotice.failed(batch.user, what: what, where: where, reason: batch.summary["error"].presence || I18n.t("distribution_batches.failed"))
    end
end
