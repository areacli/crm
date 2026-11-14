module Payments
  module Providers
    # Base dos adaptadores: o manifesto, as modalidades (as dos contratos que o adaptador inclui) e as operações comuns.
    class Base
      class NotAvailable < Error; end

      CONTRACTS = { "boleto" => Boleto, "pix" => Pix, "card" => Card }.freeze

      def manifest = raise(NotImplementedError, "#{self.class} precisa declarar o manifesto")

      def modalities = CONTRACTS.select { |_name, contract| self.class.include?(contract) }.keys

      def supports?(modality) = modalities.include?(modality.to_s)

      # Chama o fornecedor para conferir as credenciais. Devolve ConnectionResult.
      def test_connection(account) = raise(NotAvailable, I18n.t("payments.accounts.test.unavailable"))

      # Lê o aviso do fornecedor (parte D, R281): confere a autenticidade do jeito dele (levanta `InvalidSignature`) e devolve Array de Notification
      # (vazio quando o aviso não traz nada, como o teste de cadastro do webhook). `context`: { remote_ip:, query: } do pedido, para quem autentica por IP ou pela URL.
      # Só lê e confere: nunca chama o fornecedor (a resposta ao aviso tem de ser rápida).
      def parse_notification(account, body:, headers:, context: {}) = raise(NotImplementedError, "#{self.class} não lê avisos")

      # Aviso por fornecedor (12, revisão 6, R284w): o fornecedor que avisa por aplicação (`webhook: "provider"` no manifesto) confere aqui a assinatura do
      # jeito dele (levanta `InvalidSignature`) e devolve `[conta conectada, Array de Notification]`; a rota acha a integração pela conta conectada e pelo
      # instrumento. Só lê e confere: nunca chama o fornecedor.
      def parse_provider_notification(body:, headers:, context: {}) = raise(NotAvailable, I18n.t("payments.webhook_registration.unavailable"))

      # Completa o aviso, no job (R283): o que só traz um token vira os avisos de verdade, consultando o fornecedor. O padrão devolve o próprio aviso.
      def expand_notification(account, notification) = [ notification ]

      # Lista de pagos do período (12, revisão 4, R284b e R284c): os pagamentos (e devoluções) que o fornecedor mostra de `from` a `to`, como `Notification`
      # com o MESMO `event_id` que o webhook daria ao mesmo pagamento, para os dois caminhos se encontrarem num aviso só. Opcional: quem tem declara
      # `paid_list` no manifesto.
      def list_paid(account, from:, to:) = raise(NotAvailable, I18n.t("payments.paid_list.unavailable"))

      # Cadastra no fornecedor o endereço do nosso webhook (R284g). Opcional; chamado só pela tarefa de operação `crm:payments:register_webhook`.
      def register_webhook(account) = raise(NotAvailable, I18n.t("payments.webhook_registration.unavailable"))

      # Quando a lista de pagos da modalidade roda (`paid_list` do manifesto): `{ every: minutos }` ou `{ daily_at: "HH:MM" }` na hora de Brasília; nil = não tem.
      def paid_list_schedule(modality) = manifest.capabilities.dig(:paid_list, modality.to_s)

      # Janela diária em que a API da modalidade não atende (`quiet_hours: { "boleto" => "00:00-03:00" }` no manifesto, hora de Brasília; R284h).
      # Devolve o fim da janela (quando se pode chamar de novo) se `now` está dentro dela, ou nil.
      def quiet_until(modality, now = Time.current)
        window = manifest.capabilities.dig(:quiet_hours, modality.to_s).to_s.match(/\A(\d{2}):(\d{2})-(\d{2}):(\d{2})\z/) or return
        local = now.in_time_zone("America/Sao_Paulo")
        length = ((window[3].to_i * 60 + window[4].to_i) - (window[1].to_i * 60 + window[2].to_i)) % 1440
        [ local.beginning_of_day - 1.day, local.beginning_of_day ].each do |day|
          begins = day.change(hour: window[1].to_i, min: window[2].to_i)
          ends = begins + length.minutes
          return ends if local >= begins && local < ends
        end
        nil
      end

      def quiet?(modality, now = Time.current) = !quiet_until(modality, now).nil?

      private
        def not_implemented(modality, operation) = raise(NotImplementedError, "#{self.class.name} não implementa #{operation} (#{modality})")
    end
  end
end
