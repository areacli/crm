# A casca da SPA (decisão 0025): uma página só, com o bootstrap do OpenUI5, o tema da marca e a configuração inicial. Sem sessão, a mesma
# casca abre a entrada (login). A CSP é a da casca: sem `unsafe-eval`, o OpenUI5 carregado de forma assíncrona e do próprio servidor.
class ShellController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_password_change
  layout false

  content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    # O OpenUI5 grava estilo em atributos ao desenhar alguns controles (CSP do OpenUI5, "style-src").
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob
    policy.font_src :self
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :none
  end

  def show
    @configuracao = Shell::Configuration.new(authenticated? ? Current.user : nil).as_json
  end
end
