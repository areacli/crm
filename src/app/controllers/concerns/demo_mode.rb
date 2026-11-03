# Modo de demonstração pública (CRM_DEMO=1): fecha o que a vitrine não deixa alterar e troca por texto fictício o que o visitante digita
# (`Demo::Restrictions`). Sem CRM_DEMO, nada disto roda.
module DemoMode
  extend ActiveSupport::Concern

  included do
    before_action :apply_demo_restrictions, if: -> { Demo.enabled? }
  end

  private
    def apply_demo_restrictions
      if Demo::Restrictions.closed?(controller_path, action_name, request.request_method)
        # Pedido da SPA (decisão 0025): a mensagem em JSON, que a tela mostra; página do servidor: de volta, com o aviso.
        return render(json: { mensagem: Demo::Restrictions::MESSAGE }, status: :forbidden) if request.format.json?

        redirect_back_or_to summary_path, alert: Demo::Restrictions::MESSAGE, status: :see_other
      else
        Demo::Restrictions.scrub!(params, controller_path, action_name)
      end
    end
end
