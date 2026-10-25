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

    def back_to_membership(**flash) = redirect_to(membership_path(@membership), status: :see_other, **flash)
end
