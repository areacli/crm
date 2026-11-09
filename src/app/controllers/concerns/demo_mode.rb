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
        refuse_in_demo
      else
        Demo::Restrictions.scrub!(params, controller_path, action_name)
      end
    end

    # A SPA não segue o redirecionamento: a edição na linha recebe a mensagem junto do campo, a tela que só serve para alterar (nova integração) mostra a
    # mensagem no lugar dela, e a gravação termina com o aviso de recusa, sem fechar o que foi digitado em outro lugar.
    def refuse_in_demo
      return redirect_back_or_to(root_path, alert: Demo::Restrictions::MESSAGE, status: :see_other) unless spa?
      return inline_refuse(Demo::Restrictions::MESSAGE) if inline?
      return render("demo/closed") if request.get? || request.head?

      panel_finish(root_path, notice: Demo::Restrictions::MESSAGE, tom: "danger")
    end
end
