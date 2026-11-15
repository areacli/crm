module Payments
  # Conexão por autorização de uma integração (12, revisão 5, R284k e R284l). O gestor com a permissão 14 começa ("Conectar ao <fornecedor>"), vai à
  # página de autorização do fornecedor com um `state` de uso único guardado na sessão dele, e volta à rota fixa `/configuracao/integracoes/conexao/retorno`,
  # onde o código vira tokens. Os tokens ficam nos segredos cifrados da integração (R262); o estado da conexão, sem segredo, em `config`.
  #
  # A renovação é daqui, para qualquer fornecedor: quando faltam 5 minutos para o token vencer, ou depois de um 401 com o token que falhou, com a linha da
  # integração travada (o fornecedor invalida o token de renovação anterior a cada renovação: duas renovações ao mesmo tempo desconectariam a integração).
  # Recusada a renovação, a integração fica desconectada, o sino avisa quem tem a permissão 14 no credor e toda emissão falha sem chamada.
  #
  # A aplicação da instalação no fornecedor (`client_id`, `client_secret`, `platform_token`, por fornecedor e ambiente) vem das credenciais cifradas do
  # Rails (`payments.connect.<fornecedor>.<ambiente>`) ou, na falta delas, de `CRM_CONNECT_<FORNECEDOR>_<AMBIENTE>_<CAMPO>`. Nunca da tela.
  class Connection
    class Refused < StandardError; end

    STATE_TTL = 10.minutes
    RENEW_MARGIN = 5.minutes
    SESSION_KEY = :payment_connection
    RETURN_PATH = "/configuracao/integracoes/conexao/retorno".freeze
    # `webhook_secret`: o segredo do webhook da aplicação, para o fornecedor que avisa por aplicação (12, revisão 6, R284w).
    APP_FIELDS = %w[client_id client_secret platform_token webhook_secret].freeze

    def self.authorization?(account) = account.provider_available? && account.manifest.capabilities[:credentials] == "authorization"

    def self.connected?(account) = account.config["connection_state"] == "connected" && account.secrets["access_token"].present?

    # A aplicação da instalação no fornecedor, ou nil se não configurada.
    def self.app(provider, environment)
      stored = Rails.application.credentials.dig(:payments, :connect, provider.to_sym, environment.to_sym)
      values = APP_FIELDS.to_h { |field| [ field.to_sym, (stored && stored[field.to_sym]).presence || ENV["CRM_CONNECT_#{provider.upcase}_#{environment.upcase}_#{field.upcase}"].presence ] }
      values if values[:client_id] && values[:client_secret]
    end

    def self.redirect_uri = (base = WebhookUrl.base) && "#{base}#{RETURN_PATH}"

    def initialize(actor = nil) = @actor = actor

    # Começa: guarda o `state` na sessão de quem pediu e devolve o endereço da autorização no fornecedor.
    def start(account, session, now: Time.current)
      raise Refused, I18n.t("payments.connection.not_authorization") unless self.class.authorization?(account)

      app = self.class.app(account.provider, account.environment) or raise Refused, I18n.t("payments.connection.no_app", provider: account.manifest.label)
      redirect_uri = self.class.redirect_uri or raise Refused, I18n.t("payments.connection.no_public_url")
      state = SecureRandom.urlsafe_base64(32)
      session[SESSION_KEY] = { "state" => state, "account_id" => account.id, "user_id" => @actor.id, "expires_at" => (now + STATE_TTL).to_i }
      account.adapter.authorization_url(account, app: app, state: state, redirect_uri: redirect_uri)
    end

    # A volta do fornecedor: confere o `state` (de uso único, desta sessão, deste usuário, no prazo) e troca o código pelos tokens. Devolve a integração.
    # O `state` sai da sessão antes de qualquer outra coisa: nem a recusa nem o erro deixam usá-lo de novo.
    def finish(session, state:, code:, error: nil, now: Time.current)
      stored = session.delete(SESSION_KEY)
      stored = stored.to_h.stringify_keys if stored
      valid = stored && state.present? && ActiveSupport::SecurityUtils.secure_compare(stored["state"].to_s, state.to_s) &&
              stored["user_id"] == @actor.id && stored["expires_at"].to_i > now.to_i
      raise Refused, I18n.t("payments.connection.bad_state") unless valid

      account = PaymentAccount.find(stored["account_id"])
      yield account if block_given? # a política confere a permissão 14 no credor da integração
      if error.present? || code.blank?
        log(account, "connection_failed", note: I18n.t("payments.connection.denied"))
        raise Refused, I18n.t("payments.connection.denied")
      end

      app = self.class.app(account.provider, account.environment) or raise Refused, I18n.t("payments.connection.no_app", provider: account.manifest.label)
      tokens = account.adapter.exchange_authorization_code(account, app: app, code: code.to_s, redirect_uri: self.class.redirect_uri)
      store(account, tokens, now: now)
      log(account, "connected", note: tokens.account_label)
      # A troca de fornecedor que esperava esta conexão se completa agora (16, revisão 1, R373c).
      AccountManager.new(@actor).complete_replacement(account) if account.replaces_id && !account.active?
      account
    rescue Providers::Error => error
      log(account, "connection_failed", note: error.message) if account
      raise Refused, error.message
    end

    def disconnect(account, now: Time.current)
      account.with_lock do
        account.update!(secrets: account.secrets.except("access_token", "refresh_token"),
                        config: account.config.merge("connection_state" => "disconnected", "disconnected_at" => now.iso8601).except("token_expires_at"))
      end
      log(account, "disconnected")
      account
    end

    # O token de acesso que vale agora, renovado se for preciso. `stale`: o token que o fornecedor acabou de recusar (401); só se renova se ele ainda
    # for o guardado (outra chamada pode ter renovado no meio), e assim duas recusas ao mesmo tempo dão uma renovação só.
    def access_token(account, stale: nil, now: Time.current)
      raise Providers::Error, I18n.t("payments.connection.disconnected", provider: account.manifest.label) unless self.class.connected?(account)
      return account.secrets["access_token"] unless stale || expiring?(account, now)

      # A perda da conexão é gravada dentro da trava e só depois vira erro: levantado lá dentro, desfaria a própria gravação.
      outcome = account.with_lock do
        current = account.secrets["access_token"]
        next [ :lost, nil ] unless self.class.connected?(account)
        next [ :ok, current ] if stale ? current != stale : !expiring?(account, now)

        renew(account, now)
      end
      raise Providers::Error, I18n.t("payments.connection.disconnected", provider: account.manifest.label) if outcome.first == :lost

      outcome.last
    end

    private
      def expiring?(account, now)
        expires_at = account.config["token_expires_at"].presence
        expires_at.present? && Time.iso8601(expires_at) <= now + RENEW_MARGIN
      end

      # Dentro da trava: troca o token de renovação pelos dois novos, gravados juntos. Recusa do fornecedor desconecta; falha de rede só sobe (tenta depois).
      def renew(account, now)
        app = self.class.app(account.provider, account.environment) or raise Providers::Error, I18n.t("payments.connection.no_app", provider: account.manifest.label)
        refresh = account.secrets["refresh_token"].presence or return lose(account, now, I18n.t("payments.connection.no_refresh_token"))
        tokens = account.adapter.refresh_authorization(account, app: app, refresh_token: refresh)
        store(account, tokens, now: now, renewal: true)
        log(account, "connection_renewed")
        [ :ok, tokens.access_token ]
      rescue Providers::AuthorizationRefused => error
        lose(account, now, error.message)
      end

      def store(account, tokens, now:, renewal: false)
        secrets = account.secrets.merge("access_token" => tokens.access_token, "refresh_token" => tokens.refresh_token.presence || account.secrets["refresh_token"]).compact
        config = account.config.merge("connection_state" => "connected", "token_expires_at" => tokens.expires_at&.iso8601).compact
        config = config.merge("connected_at" => now.iso8601, "connection_label" => tokens.account_label.to_s.first(100).presence).compact.except("disconnected_at") unless renewal
        # A conta conectada e os valores públicos (R284x), na conexão e em cada renovação que os traga.
        config = config.merge("connection_account_id" => tokens.account_id.to_s.presence).compact
        config = config.merge(tokens.public_values.to_h.transform_keys { |key| "connection_#{key}" }.compact_blank)
        account.update!(secrets: secrets, config: config)
      end

      def lose(account, now, reason)
        account.update!(secrets: account.secrets.except("access_token", "refresh_token"),
                        config: account.config.merge("connection_state" => "disconnected", "disconnected_at" => now.iso8601).except("token_expires_at"))
        log(account, "connection_lost", note: reason)
        recipients(account.tenant).each do |user|
          Notice.create!(user: user, kind: "payment_connection_lost", data: { account: account.nickname, tenant_name: account.tenant.name, provider: account.manifest.label })
        end
        [ :lost, nil ]
      end

      def recipients(tenant)
        User.where(active: true, id: tenant.memberships.active.joins(:profile).where("profiles.permissions @> ?", [ "change_financial_policies" ].to_json).select(:user_id))
      end

      def log(account, event, note: nil)
        Change.record!(tenant_id: account.tenant_id, user: @actor, subject_type: "payment_account", subject_id: account.id, event: event, field: "connection",
                       before: nil, after: nil, note: note.to_s.first(300).presence)
      end
  end
end
