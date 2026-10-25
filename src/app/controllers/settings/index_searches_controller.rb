module Settings
  # "Buscar índices agora" (08, R147, revisão 2): a mesma busca da tarefa diária, uma de cada vez para o sistema todo. Permissão 14.
  class IndexSearchesController < ApplicationController
    def create
      authorize :index, :search?, policy_class: IndexPolicy
      if Indexes::Fetch.running?
        redirect_to settings_indexes_path, alert: t("indexes.adjust.search_running"), status: :see_other
      else
        FetchIndexesJob.perform_later(true)
        redirect_to settings_indexes_path, notice: t("indexes.adjust.search_started"), status: :see_other
      end
    end
  end
end
