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
      # Na ficha da SPA, o perfil se edita na linha (design system, 7.1); a recusa (R41, o credor sem gestão) fica junto da lista.
      return inline_finish(profile.name, aviso: t(".done")) if inline?

      back_to_membership notice: t(".done")
    rescue Access::Refused => error
      return inline_refuse(error.message) if inline?

      @profiles = @membership.tenant.profiles.order(:name)
      panel_error(error.message, membership_path(@membership), :edit)
    end
  end
end
