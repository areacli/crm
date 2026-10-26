module Payments
  # Cadastro das contas de pagamento (12, R260 a R269). A permissão 14 já foi conferida pela política no credor da conta; aqui ficam as
  # regras de dados e o registro de cada ato no histórico, sempre sem valor de campo secreto ou de arquivo (R268).
  class AccountManager
    def initialize(actor) = @actor = actor

    def create(tenant:, channel:, modality:, provider:, environment:, nickname:, values: {})
      account = tenant.payment_accounts.build(channel: channel, modality: modality, provider: provider, environment: environment, nickname: nickname)
      account.assign_values(**values)
      ApplicationRecord.transaction do
        account.save!
        log(account, "created", "nickname", nil, account.nickname)
      end
      account
    end

    # Apelido e campos comuns mudam com antes e depois; segredo e arquivo trocados registram só o nome do campo.
    def update(account, nickname:, channel: nil, values: {})
      account.nickname = nickname
      account.channel = channel if channel
      account.assign_values(**values)
      ApplicationRecord.transaction do
        before_config = account.config_was || {}
        account.save!
        log(account, "updated", "nickname", account.nickname_before_last_save, account.nickname) if account.saved_change_to_nickname?
        log(account, "updated", "channel", PaymentChannel.find_by(id: account.channel_id_before_last_save)&.code, account.channel.code) if account.saved_change_to_channel_id?
        config_changes(before_config, account.config).each { |name, (before, after)| log(account, "updated", name, before, after) }
        account.replaced_secrets.uniq.each { |name| log(account, "secret_replaced", name, nil, nil) }
        account.replaced_files.uniq.each { |name| log(account, "file_replaced", name, nil, nil) }
      end
      account
    end

    def activate(account) = switch(account, true, "activated")

    def deactivate(account) = switch(account, false, "deactivated")

    # R269: a conta que já emitiu instrumento só se desativa (a partir da parte B); a sem emissão se apaga.
    def destroy(account)
      raise Access::Refused, I18n.t("payments.accounts.in_use") if account.used?

      ApplicationRecord.transaction do
        log(account, "deleted", "nickname", account.nickname, nil)
        account.destroy!
      end
    end

    # Gera ou troca o segredo do webhook e o devolve em claro, uma única vez (R265).
    def regenerate_webhook_secret(account)
      secret = account.rotate_webhook_secret!
      log(account, "webhook_secret_generated", "webhook_secret", nil, nil)
      secret
    end

    def test_connection(account)
      result = AccountTester.new.call(account)
      log(account, "tested", "connection", nil, result.status || "unavailable", note: result.message)
      result
    end

    private
      def switch(account, active, event)
        account.update!(active: active)
        log(account, event, "active", (!active).to_s, active.to_s)
        account
      end

      def config_changes(before, after)
        (before.keys | after.keys).filter_map { |name| [ name, [ before[name], after[name] ] ] if before[name] != after[name] }.to_h
      end

      def log(account, event, field, before, after, note: nil)
        Change.record!(tenant_id: account.tenant_id, user: @actor, subject_type: "payment_account", subject_id: account.id, event: event, field: field,
                       before: before.to_s.presence, after: after.to_s.presence, note: note.to_s.first(300).presence)
      end
  end
end
