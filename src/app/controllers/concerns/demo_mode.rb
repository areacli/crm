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
        redirect_back_or_to root_path, alert: Demo::Restrictions::MESSAGE, status: :see_other
      else
        Demo::Restrictions.scrub!(params, controller_path, action_name)
      end
    end
end
