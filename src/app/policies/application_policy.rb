# Política padrão: tudo negado. Cada modelo declara o que permite, pela permissão do usuário no credor do registro (MT-3).
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve = raise(NotImplementedError, "#{self.class} precisa dizer o que o usuário vê")

    private
      attr_reader :user, :scope
  end

  private
    def permitted?(permission, tenant = record.tenant_id) = user.permitted?(permission, tenant)
end
