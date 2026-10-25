module Settings
  # Tela de índices do Banco Central (08, R147), uma aba da configuração: os últimos 24 meses das quatro séries (globais), a origem de cada
  # valor, a correção de cada credor e a situação da busca. Ver: permissão 1, 4 ou 14; corrigir e "Buscar índices agora": 14 (R157, R158).
  class IndexesController < ApplicationController
    def show
      authorize :index, :show?, policy_class: IndexPolicy
      user = Current.user
      ids = %w[view_portfolio change_settings change_financial_policies].flat_map { |permission| user.tenant_ids_with(permission) }.uniq
      @tenants = Tenant.where(id: ids).order(:name).to_a
      @can_correct = user.tenant_ids_with("change_financial_policies")
      @grid = Indexes::Grid.new(ids, page: params[:page])
      load_runs
      render partial: "settings/indexes/page" if htmx_fragment?
    end

    private
      def load_runs
        runs = TaskRun.where(tenant_id: nil, name: Indexes::Fetch::NAME).recent
        @runs = runs.limit(5).to_a
        @last_success = runs.where(status: "succeeded").first
        @last_failure = runs.where(status: "failed").first
        @running = Indexes::Fetch.running?
      end
  end
end
