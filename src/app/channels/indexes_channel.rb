# Tela de índices (08, R147): quem vê índices em algum credor (permissão 1, 4 ou 14) assina o canal global; o evento é só de invalidação.
class IndexesChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user && %w[view_portfolio change_settings change_financial_policies].any? { |permission| current_user.permitted_anywhere?(permission) }

    stream_for "all"
  end
end
