module Memberships
  # Mudar o perfil do vínculo (R32): outra pessoa faz, nunca o próprio usuário (PD7), e o credor nunca fica sem gestão (R41).
  class ProfilesController < ApplicationController
    include MembershipAction

    def edit
      @profiles = @membership.tenant.profiles.order(:name)
    end

    def update
      profile = @membership.tenant.profiles.find(params.expect(membership: [ :profile_id ])[:profile_id])
      manager.change_profile(@membership, profile)
      back_to_membership notice: t(".done")
    rescue Access::Refused => error
      @profiles = @membership.tenant.profiles.order(:name)
      panel_error(error.message, membership_path(@membership), :edit)
    end
  end
end
