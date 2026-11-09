# Trocar a própria senha (R39) e definir a senha no primeiro acesso, com a temporária (R38). A senha nova segue a R26 e não repete a
# anterior; as outras sessões do usuário são encerradas. Nada disso registra a senha (R42).
class PasswordsController < ApplicationController
  # Serve página ou arquivo direto, fora da casca (impressão, download, entrada).
  skip_before_action :redirect_page_to_shell
  skip_before_action :require_password_change

  # O formulário vem para a casca (o diálogo "Trocar a senha" e o "Defina sua senha" da senha temporária); o endereço como página leva à raiz.
  def edit
    return redirect_to(root_path) unless spa?

    @user = Current.user
  end

  def update
    @user = Current.user
    attributes = params.expect(password: %i[ current_password password password_confirmation ])
    first_access = @user.temporary_password?

    if @user.change_password(attributes[:password], attributes[:password_confirmation], current: attributes[:current_password], require_current: !first_access)
      @user.sessions.where.not(id: Current.session.id).destroy_all
      AccessEvent.record("password_changed", request: request, user: @user, tenant_id: nil, actor: @user, details: { first_access: first_access })
      return panel_finish(root_path, notice: t(".done")) if spa?

      redirect_to root_path, notice: t(".done"), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end
end
