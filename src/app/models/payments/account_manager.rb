module Payments
  # Cadastro das contas de pagamento (12, R260 a R269). A permissão 14 já foi conferida pela política no credor da conta; aqui ficam as
  # regras de dados e o registro de cada ato no histórico, sempre sem valor de campo secreto ou de arquivo (R268).
  class AccountManager
    def initialize(actor) = @actor = actor

    # `replaces`: a integração ativa que a nova substitui ("Trocar fornecedor", 16, revisão 1, R373c). Com credenciais, a anterior sai e a nova entra no mesmo
    # ato (primeiro sai a anterior: só uma ativa por credor, meio e ambiente). Com conexão por autorização, a nova nasce desativada, e a troca se completa
    # na volta da conexão (`complete_replacement`); até lá, a anterior continua emitindo.
    def create(tenant:, modality:, provider:, environment:, nickname:, account_code:, values: {}, replaces: nil)
      account = tenant.payment_accounts.build(modality: modality, provider: provider, environment: environment, nickname: nickname, account_code: account_code, replaces: replaces)
      account.assign_values(**values)
      # O fornecedor que grava a URL do aviso em cada pedido recebe a chave da URL já na criação (12, revisão 5, R284m): ela nunca troca com o segredo.
      account.secrets = account.secrets.merge("webhook_url_key" => SecureRandom.base58(40)) if account.provider_available? && WebhookUrl.per_charge?(account)
      waits = replaces && account.provider_available? && Connection.authorization?(account)
      account.active = false if waits
      ApplicationRecord.transaction do
        if replaces
          replaces.lock!
          # Só a ativa se troca: a que saiu de uso entre a página e o "Salvar" recusa a troca.
          unless replaces.active?
            account.errors.add(:base, I18n.t("payments.methods.replace.not_active"))
            raise ActiveRecord::RecordInvalid, account
          end
          retire(replaces, account) unless waits
        end
        account.save!
        log(account, replaces ? "replacing" : "created", "nickname", nil, account.nickname, note: replaces&.nickname)
      end
      account
    end

    # Completa a troca à espera da conexão: a anterior sai e a nova entra, no mesmo ato. Sem troca pendente, não faz nada.
    def complete_replacement(account)
      return account unless account.replaces_id && !account.active?

      ApplicationRecord.transaction do
        previous = account.replaces&.lock!
        retire(previous, account) if previous&.active?
        account.update!(active: true)
        log(account, "replacement_completed", "active", "false", "true", note: previous&.nickname)
      end
      account
    end

    # Apelido e campos comuns mudam com antes e depois; segredo e arquivo trocados registram só o nome do campo.
    def update(account, nickname:, account_code: nil, values: {})
      account.nickname = nickname
      account.account_code = account_code unless account_code.nil?
      account.assign_values(**values)
      ApplicationRecord.transaction do
        before_config = account.config_was || {}
        account.save!
        log(account, "updated", "nickname", account.nickname_before_last_save, account.nickname) if account.saved_change_to_nickname?
        log(account, "updated", "account_code", account.account_code_before_last_save, account.account_code) if account.saved_change_to_account_code?
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
      # A integração substituída sai de uso, com o nome da que entra no histórico.
      def retire(previous, account)
        previous.update!(active: false)
        log(previous, "replaced", "active", "true", "false", note: account.nickname)
      end

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
