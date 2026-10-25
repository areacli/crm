# Base da página pública de pagamento (12, parte C, R277 a R280). Sem login e sem a sessão do back office (não herda do ApplicationController): a
# autorização é o token do endereço, que vale 256 bits. Token inexistente, vencido ou cancelado responde igual (404 com a mesma página), sem dizer qual.
#
# Segurança da página: sem cache; sem indexação (cabeçalho e meta); sem referenciador; Permissions-Policy fechada; política de segurança de conteúdo
# própria, que libera só o que o fornecedor de cartão declara no manifesto (e mais nada); limite de requisições por IP.
class CheckoutBaseController < ActionController::Base
  layout "pagamento"

  before_action :set_security_headers
  rate_limit to: 120, within: 1.minute, name: "pages", with: -> { head :too_many_requests }
  before_action :load_checkout

  rescue_from ActionController::InvalidAuthenticityToken, ActionController::ParameterMissing do
    render "checkouts/expired_page", status: :unprocessable_content, layout: false
  end

  helper_method :checkout

  private
    attr_reader :checkout

    def set_security_headers
      response.headers["Cache-Control"] = "no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["X-Frame-Options"] = "DENY"
      response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
      response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
      # O Rails ainda emite a política de permissões com o nome antigo (Feature-Policy); o cabeçalho de hoje vai direto. Só o pagamento fica com a própria origem.
      response.headers["Permissions-Policy"] = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(self), usb=(), interest-cohort=()"
    end

    # Um 404 só, para qualquer motivo: o link não existe, venceu ou foi cancelado. Não revela qual.
    def load_checkout
      found = PaymentCheckout.find_by(token: params[:token].to_s)
      return render_unavailable unless found&.available?

      @checkout = found

      Payments::Checkouts.settle_stale(@checkout)
      apply_content_security_policy
    end

    def render_unavailable
      apply_content_security_policy unless request.content_security_policy
      render "checkouts/unavailable", status: :not_found, formats: :html, content_type: "text/html"
    end

    # A política da página (R278): nada vem de fora, exceto os domínios que o adaptador do cartão declara para a biblioteca dele (e só se o link oferece
    # cartão). `script-src` leva também o nonce (o importmap e o módulo de entrada são scripts embutidos).
    def apply_content_security_policy
      return unless request.format.html? || checkout.nil?

      hosts = card_hosts
      socket = request.ssl? ? "wss://#{request.host_with_port}" : "ws://#{request.host_with_port}"
      request.content_security_policy = ActionDispatch::ContentSecurityPolicy.new do |policy|
        policy.default_src :none
        policy.script_src :self, *hosts[:script]
        policy.connect_src :self, socket, *hosts[:connect]
        hosts[:frame].any? ? policy.frame_src(*hosts[:frame]) : policy.frame_src(:none)
        policy.img_src :self, :data, *hosts[:img]
        policy.style_src :self
        policy.font_src :self
        policy.base_uri :none
        policy.form_action :self
        policy.frame_ancestors :none
        policy.object_src :none
      end
    end

    def card_hosts
      empty = { script: [], connect: [], frame: [], img: [] }
      return empty unless checkout&.offers?("card")

      account = Payments::Checkouts.card_account(checkout.tenant, checkout.environment)
      account&.provider_available? ? empty.merge(account.adapter.card_checkout_hosts(account)) : empty
    end
end
