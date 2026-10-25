# Avisos de um usuário: cada pessoa assina só o canal dela (sem parâmetro, o canal é o do usuário da conexão). A difusão leva só o
# sinal "notice-created"; o sino busca a lista pelo htmx (decisão 0020).
class NoticesChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    stream_for current_user
  end
end
