# Gera (ou troca) o segredo que assina o webhook do canal. O segredo aparece uma única vez, na tela de edição (como a senha temporária).
module Settings
  module Channels
    class WebhookSecretsController < ApplicationController
      def create
        channel = PaymentChannel.find(params[:channel_id])
        authorize channel, :update?
        flash[:webhook_secret] = Payments::ChannelManager.new(Current.user).regenerate_secret(channel)
        redirect_to edit_settings_channel_path(channel), status: :see_other
      end
    end
  end
end
