# Ação sobre um vínculo de usuário (ficha em /usuarios/:id): carrega o vínculo, confere a permissão 10 no credor dele (recusa vira 404
# registrada) e entrega o gerenciador das regras. As ações aninhadas voltam para a ficha.
module MembershipAction
  extend ActiveSupport::Concern

  included do
    before_action :set_membership
  end

  private
    def set_membership
      @membership = Membership.includes(:user, :tenant, :profile).find(params[:membership_id] || params[:id])
      authorize @membership, :update?
    end

    def manager = Access::UserManager.new(Current.user, request: request)

    # Termina a ação do painel (modal): fecha, mostra o aviso e atualiza a ficha do vínculo; sem JavaScript, volta à ficha.
    def back_to_membership(notice: nil) = panel_finish(membership_path(@membership), notice: notice, atualizar: true)
end
