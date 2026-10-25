module Memberships
  # Redefinir a senha (R37): gera outra senha temporária, mostrada uma única vez. A senha é da pessoa (R36a), então só se ela não atua
  # em outro credor.
  class PasswordResetsController < ApplicationController
    include MembershipAction
    before_action { authorize @membership, :edit_personal? }

    def create
      password = manager.reset_password(@membership)
      flash[:temporary_password] = { "email" => @membership.user.email_address, "password" => password }
      back_to_membership
    end
  end
end
