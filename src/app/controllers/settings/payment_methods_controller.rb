# Página "Meios de pagamento" (16, revisão 1, R373a): um quadro por meio que o CRM emite (boleto, Pix, cartão de crédito), com a integração ativa de
# cada ambiente, a troca à espera da conexão e as desativadas no detalhe. É de um credor por vez, com a permissão 14 nele (12, R267); quem a tem em
# mais de um escolhe o credor no filtro, sem "Todos".
module Settings
  class PaymentMethodsController < ApplicationController
    def index
      authorize PaymentAccount, :index?
      @tenants = Tenant.where(id: Current.user.tenant_ids_with("change_financial_policies")).order(:name)
      @tenant = params[:credor].present? ? @tenants.find_by(id: params[:credor]) : @tenants.first
      return head :not_found unless @tenant

      @accounts = policy_scope(PaymentAccount).where(tenant_id: @tenant.id).includes(:channel).order(:created_at).to_a
      # Os meios que algum fornecedor instalado emite; um meio novo entra quando algum fornecedor o emitir (R373a).
      @modalities = Payments::Providers::MODALITIES.select { |modality| Payments::Providers.for_modality(modality).any? }
      retired = @accounts.reject(&:active?).map(&:id)
      @retired_at = Change.where(tenant_id: @tenant.id, subject_type: "payment_account", subject_id: retired, event: %w[deactivated replaced]).group(:subject_id).maximum(:occurred_at)
      @open_counts = PaymentInstrument.where(account_id: retired, open: true).group(:account_id).count
      render partial: "settings/payment_methods/result" if fragment?
    end
  end
end
