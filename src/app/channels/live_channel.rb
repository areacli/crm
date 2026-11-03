# Tempo real com dados (decisão 0025): um fluxo por usuário. A conexão marca a presença do usuário (contando as abas do navegador), e
# `LiveBroadcastJob` só monta mensagens para quem está presente, cada uma no contexto do próprio usuário (RLS e políticas).
class LiveChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user && !current_user.temporary_password?

    Live::Presence.enter(current_user)
    stream_for current_user
  end

  def unsubscribed
    Live::Presence.leave(current_user) if current_user
  end
end
