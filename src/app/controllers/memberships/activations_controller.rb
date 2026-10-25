module Memberships
  # Reativar (create) e desativar (destroy) o vínculo no credor (R40); o usuário segue nos outros credores. Ninguém desativa a si mesmo.
  class ActivationsController < ApplicationController
    include MembershipAction

    def create
      manager.set_active(@membership, true)
      back_to_membership notice: t(".done")
    end

    def destroy
      manager.set_active(@membership, false)
      back_to_membership notice: t(".done")
    end
  end
end
