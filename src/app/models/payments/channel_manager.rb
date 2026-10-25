module Payments
  # Cadastro dos canais de recebimento do credor (R45, revisão 7). A permissão 4 já foi conferida pela política no credor do canal;
  # aqui ficam as regras de dados e o registro de cada mudança (quem, quando, antes e depois).
  class ChannelManager
    def initialize(actor) = @actor = actor

    def create(tenant:, kind:, code:, description:)
      channel = tenant.payment_channels.build(kind: kind, code: code, description: description)
      ApplicationRecord.transaction do
        channel.save!
        log(channel, "created", "code", nil, channel.code)
      end
      channel
    end

    # Descrição, tipo e situação mudam sempre; o código só enquanto o canal não tem pagamento (é o que a planilha traz).
    def update(channel, kind:, code:, description:, active:)
      attributes = { kind: kind, description: description, active: active }
      attributes[:code] = code unless channel.used?
      channel.assign_attributes(attributes)
      ApplicationRecord.transaction do
        channel.changes.each { |field, (before, after)| log(channel, "updated", field, before, after) if field != "webhook_secret" }
        channel.save!
      end
      channel
    end

    # R45 (revisão 7): só o canal sem pagamento se apaga, com confirmação.
    def destroy(channel)
      raise Access::Refused, I18n.t("payments.channels.in_use") if channel.used?

      ApplicationRecord.transaction do
        log(channel, "deleted", "code", channel.code, nil)
        channel.destroy!
      end
    end

    # Gera (ou troca) o segredo do webhook e o devolve em claro, uma única vez. O segredo antigo deixa de valer; o registro não o guarda.
    def regenerate_secret(channel)
      secret = channel.regenerate_webhook_secret!
      log(channel, "webhook_secret_generated", "webhook_secret", nil, nil)
      secret
    end

    private
      def log(channel, event, field, before, after)
        Change.create!(tenant_id: channel.tenant_id, user: @actor, subject_type: "channel", subject_id: channel.id, event: event, field: field,
                       before: before.to_s.presence, after: after.to_s.presence)
      end
  end
end
