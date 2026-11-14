module Webhooks
  # Aviso por fornecedor (12, revisão 6, R284w): o fornecedor que configura o webhook uma vez por aplicação (Mercado Pago, API Orders) chama uma rota só. O
  # adaptador confere a assinatura com o segredo do webhook da aplicação da instalação e diz de que conta conectada é o aviso; aqui se acha, entre as
  # integrações ativas desse fornecedor ligadas a essa conta, a que emitiu o instrumento, e o aviso é guardado nela uma única vez (R282). Depois, o mesmo
  # job de sempre consulta o fornecedor antes de mudar qualquer coisa (R283). Nada aqui chama o fornecedor. Aviso que nenhuma integração reconhece: 202,
  # nada gravado (o fornecedor não deve repetir o que não é nosso).
  class PaymentProvidersController < ActionController::API
    include SystemDbRole
    MAX_BYTES = 64.kilobytes

    rate_limit to: 600, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

    def create
      name = request.path_parameters[:fornecedor].to_s
      return head :not_found unless Payments::Providers.known?(name) && Payments::Providers.manifest(name).capabilities[:webhook] == "provider"

      body = request.body.read(MAX_BYTES + 1).to_s
      return head :content_too_large if body.bytesize > MAX_BYTES

      account_ref, notifications = Payments::Providers.adapter(name).parse_provider_notification(body: body, headers: request.headers, context: context)
      accounts = account_ref.present? ? PaymentAccount.active.where(provider: name).where("config->>'connection_account_id' = ?", account_ref.to_s).to_a : []
      recorded = notifications.count do |notification|
        account = accounts.find { |candidate| notification.external_id && candidate.instruments.exists?(external_id: notification.external_id) } or next false
        event, queue = PaymentEvent.record(account, notification)
        ProcessPaymentEventJob.perform_later(event) if queue
        true
      end
      render json: { status: "received", events: recorded }, status: :accepted
    rescue Payments::Providers::InvalidSignature
      AccessEvent.record("webhook_refused", request: request, details: { provider: name })
      head :unauthorized
    rescue Payments::Providers::Error
      render json: { error: "aviso fora do formato" }, status: :unprocessable_content
    end

    private
      def context = { remote_ip: request.remote_ip, query: request.query_parameters.slice("data.id", "type", "id", "topic") }
  end
end
