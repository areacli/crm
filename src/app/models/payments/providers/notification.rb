module Payments
  module Providers
    # Aviso do fornecedor normalizado (12, parte D). `event_id` é a chave da idempotência (R282). `kind`: paid, refunded, canceled, expired, other, ou
    # check (o aviso só traz um token e o estado vem de `expand_notification`, que consulta o fornecedor). `external_id` é o identificador do fornecedor
    # (`charge_id`, `txid`); `custom_id`, o nosso; `end_to_end_id`, o do Pix. `reprocess`: o mesmo identificador pode voltar com mudança nova (a Efí
    # reusa o token enquanto a cobrança muda de estado), então o repetido reabre o aviso em vez de ser ignorado. Nada aqui é dado do pagador nem de cartão.
    Notification = Data.define(:event_id, :kind, :external_id, :amount_cents, :occurred_at, :token, :end_to_end_id, :custom_id, :previous_status, :current_status, :reprocess) do
      def initialize(event_id:, kind:, external_id: nil, amount_cents: nil, occurred_at: nil, token: nil, end_to_end_id: nil, custom_id: nil, previous_status: nil,
                     current_status: nil, reprocess: false)
        super(event_id: event_id.to_s, kind: kind.to_sym, external_id: external_id&.to_s.presence, amount_cents: amount_cents, occurred_at: occurred_at, token: token,
              end_to_end_id: end_to_end_id, custom_id: custom_id, previous_status: previous_status, current_status: current_status, reprocess: reprocess)
      end
    end
  end
end
