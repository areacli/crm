module Webhooks
  # Aviso de um fornecedor de pagamento (12, parte D, R281): uma rota por conta de pagamento. Sem sessão nem token de formulário (é o fornecedor que chama).
  # O controlador só lê e confere pelo adaptador (assinatura, HMAC na URL, IP ou certificado de cliente, cada fornecedor do seu jeito), guarda cada aviso
  # uma única vez (conta + identificador do evento, R282) e responde 2xx logo; quem consulta o fornecedor e mexe no instrumento é o job da fila `webhooks`
  # (R283). Nada aqui chama o fornecedor. 404 igual para conta inexistente, desativada de fornecedor ou sem fornecedor instalado; 401 para autenticação errada.
  class PaymentAccountsController < ActionController::API
    MAX_BYTES = 64.kilobytes

    rate_limit to: 600, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

    def create
      # Sem `params`: o corpo malformado não deve estourar na leitura dos parâmetros (o adaptador é quem lê o corpo).
      account = PaymentAccount.find_by(id: request.path_parameters[:conta])
      return head :not_found unless account&.provider_available?

      body = request.body.read(MAX_BYTES + 1).to_s
      return head :content_too_large if body.bytesize > MAX_BYTES

      notifications = account.adapter.parse_notification(account, body: body, headers: request.headers, context: context)
      notifications.each do |notification|
        event, queue = PaymentEvent.record(account, notification)
        ProcessPaymentEventJob.perform_later(event) if queue
      end
      render json: { status: "received", events: notifications.size }, status: :accepted
    rescue Payments::Providers::InvalidSignature
      AccessEvent.record("webhook_refused", tenant_id: account.tenant_id, request: request, details: { payment_account_id: account.id })
      head :unauthorized
    rescue Payments::Providers::Error
      render json: { error: "aviso fora do formato" }, status: :unprocessable_content
    end

    private
      def context
        { remote_ip: request.remote_ip, query: request.query_parameters.slice("hmac"), client_verified: request.headers["X-SSL-Client-Verify"] == "SUCCESS" }
      end
  end
end
