module Webhooks
  # Recebe o webhook de pagamento de um canal. Sem sessão nem token de formulário (é o provedor que chama): a autenticação é a assinatura
  # HMAC do corpo com o segredo do canal. O evento é guardado uma única vez (canal + identificador do evento) e processado em segundo
  # plano; o reenvio responde 200 e não processa de novo.
  class PaymentsController < ActionController::API
    MAX_BYTES = 64.kilobytes

    rate_limit to: 600, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

    def create
      channel = PaymentChannel.find_by(id: params[:channel_id])
      return head :not_found unless channel&.webhook_enabled?

      body = request.raw_post
      return head :content_too_large if body.bytesize > MAX_BYTES

      gateway = Payments::Gateway.for(channel.webhook_adapter)
      gateway.verify!(body: body, headers: request.headers, secret: channel.webhook_secret)
      payload = JSON.parse(body)
      event = gateway.event(payload)

      record = WebhookEvent.create!(tenant_id: channel.tenant_id, channel: channel, event_id: event.id, payload: payload)
      ProcessWebhookEventJob.perform_later(record)
      render json: { status: "received" }, status: :accepted
    rescue Payments::Gateway::InvalidSignature
      AccessEvent.record("webhook_refused", tenant_id: channel.tenant_id, request: request, details: { channel_id: channel.id })
      head :unauthorized
    rescue JSON::ParserError, Payments::Gateway::InvalidPayload => error
      render json: { error: error.message }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotUnique
      render json: { status: "duplicate" }, status: :ok
    end
  end
end
