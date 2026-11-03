# Auxiliares das visões JSON da SPA (decisão 0025): o selo de situação vira texto e estado do OpenUI5 (design system 17.1, o mapa das situações).
module SpaHelper
  ESTADOS = { "success" => "Success", "warning" => "Warning", "danger" => "Error", "info" => "Information", "neutral" => "None" }.freeze

  def selo(texto, tom) = { texto: texto, estado: ESTADOS.fetch(tom.to_s) }

  # A situação do vínculo (R40), na mesma ordem de `membership_status`.
  def membership_selo(membership)
    user = membership.user
    return selo("Usuário desativado", :danger) unless user.active?
    return selo("Acesso desativado", :neutral) unless membership.active?

    user.temporary_password? ? selo("Senha temporária", :info) : selo("Ativo", :success)
  end

  def promise_selo(promise) = selo(t("promises.states.#{promise.state}"), PromisesHelper::TONES.fetch(promise.state))

  def agreement_selos(agreement)
    [ selo(t("agreements.states.#{agreement.state}"), AgreementsHelper::TONES.fetch(agreement.state)), (selo("Em reversão", :danger) if agreement.reversing?) ].compact
  end
end
