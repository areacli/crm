# A casca da SPA em EasyUI (decisão 0028): carregada uma vez, com ou sem sessão. O aviso de tela pequena e a entrada ficam nela, para a pessoa saber antes de digitar a senha.
# O aviso da sessão (flash) vai pelo `menu.json`, que a casca pede logo ao abrir.
class ShellController < ApplicationController
  skip_before_action :redirect_page_to_shell
  layout "casca"
  allow_unauthenticated_access
  skip_before_action :require_password_change

  def show = flash.keep
end
