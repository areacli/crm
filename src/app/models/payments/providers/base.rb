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

      # Completa o aviso, no job (R283): o que só traz um token vira os avisos de verdade, consultando o fornecedor. O padrão devolve o próprio aviso.
      def expand_notification(account, notification) = [ notification ]

      private
        def not_implemented(modality, operation) = raise(NotImplementedError, "#{self.class.name} não implementa #{operation} (#{modality})")
    end
  end
end
