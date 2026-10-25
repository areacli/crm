module Payments
  # Teste de conexão de uma conta (12, R266): confere o certificado (vencido acusa) e chama o teste do adaptador. Grava na conta quando e como
  # foi; o fornecedor sem teste não altera o último resultado.
  class AccountTester
    def call(account, now: Time.current)
      result = expired_certificate(account, now) || run_adapter(account)
      if result.status
        account.update_columns(last_tested_at: now, last_test_status: result.status, last_test_message: result.message.to_s.first(300))
      end
      result
    end

    private
      def expired_certificate(account, now)
        expired = account.certificate_expires_on
        return unless expired && expired <= now.to_date

        Providers::ConnectionResult.new(ok: false, message: I18n.t("payments.accounts.test.certificate_expired", date: expired.strftime("%d/%m/%Y")))
      end

      def run_adapter(account)
        account.adapter.test_connection(account)
      rescue Providers::Base::NotAvailable
        Providers::ConnectionResult.new(ok: nil, message: I18n.t("payments.accounts.test.unavailable"))
      rescue Providers::Error => error
        Providers::ConnectionResult.new(ok: false, message: error.message)
      end
  end
end
