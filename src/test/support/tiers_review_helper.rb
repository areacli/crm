# A conferência do impacto roda em segundo plano (13, revisão 3): nos testes de tela, segue o redirecionamento, roda o cálculo e abre a página.
module TiersReviewHelper
  def follow_review
    assert_response :see_other
    path = URI(response.location).path
    perform_enqueued_jobs(only: TierReviewJob)
    get path
    assert_response :success
    path
  end

  def review_token = css_select("input[name='confirmation[token]']").first["value"]

  def confirm_review(tenant)
    post settings_tier_confirmation_path, params: { tenant_id: tenant.id, confirmation: { token: review_token } }
  end
end
