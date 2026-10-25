module Payments
  module Providers
    # Resultado do teste de conexão: `ok` verdadeiro (conferiu), falso (falhou) ou nil (o fornecedor não tem teste). A mensagem é curta e nunca leva credencial.
    ConnectionResult = Data.define(:ok, :message) do
      def ok? = ok == true

      def status = { true => "ok", false => "failed" }[ok]
    end
  end
end
