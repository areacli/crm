# Sinais da verificação da plataforma (`bin/rails crm:platform_check`): público e sem dado de credor.
class PlatformChannel < ApplicationCable::Channel
  STREAM = "platform".freeze

  def subscribed
    stream_from STREAM
  end
end
