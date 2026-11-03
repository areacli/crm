# Trocar a própria senha (R39) e definir a senha no primeiro acesso, com a temporária (R38). A senha nova segue a R26 e não repete a
# anterior; as outras sessões do usuário são encerradas. Nada disso registra a senha (R42). Tela da SPA (decisão 0025): responde JSON.
class PasswordsController < ApplicationController
  skip_before_action :require_password_change

  # O endereço antigo leva à tela da SPA.
  def edit
    redirect_to "#{root_path}#/senha"
  end

  def update
    @user = Current.user
    attributes = params.expect(password: %i[ current_password password password_confirmation ])
    first_access = @user.temporary_password?

    if @user.change_password(attributes[:password], attributes[:password_confirmation], current: attributes[:current_password], require_current: !first_access)
      @user.sessions.where.not(id: Current.session.id).destroy_all
      AccessEvent.record("password_changed", request: request, user: @user, tenant_id: nil, actor: @user, details: { first_access: first_access })
      render json: { mensagem: t(".done") }
    else
      render json: { erros: @user.errors.to_hash(true), mensagem: @user.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  end
end
