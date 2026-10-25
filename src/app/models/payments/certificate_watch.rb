module Payments
  # Tarefa diária (12, R264): avisa no sino de quem tem a permissão 14 no credor, uma vez por certificado, quando faltam 30 dias ou menos
  # para vencer (ou quando já venceu sem aviso). Trocar o certificado zera o controle (`certificate_warned_for`). Consulta: varredura das
  # contas ativas (dezenas de linhas).
  class CertificateWatch
    def call(today: Date.current)
      warned = 0
      PaymentAccount.active.includes(:tenant).find_each do |account|
        expires_on = account.certificate_expires_on
        next if expires_on.nil? || (expires_on - today) > PaymentAccount::WARNING_DAYS || account.certificate_warned_for == expires_on

        recipients(account.tenant).each do |user|
          Notice.create!(user: user, kind: expires_on > today ? "certificate_expiring" : "certificate_expired",
                         data: { account: account.nickname, tenant_name: account.tenant.name, expires_on: expires_on.strftime("%d/%m/%Y") })
        end
        account.update_columns(certificate_warned_for: expires_on)
        warned += 1
      end
      warned
    end

    private
      def recipients(tenant)
        User.where(active: true, id: tenant.memberships.active.joins(:profile).where("profiles.permissions @> ?", [ "change_financial_policies" ].to_json).select(:user_id))
      end
  end
end
