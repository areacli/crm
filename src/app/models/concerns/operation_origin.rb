# Origem (14, R315): o que um usuário de operação cria é da operação dele, e a origem não muda depois. Vem do contexto da requisição
# (`Operations::Context`), num lugar só, sem cada serviço precisar lembrar.
module OperationOrigin
  extend ActiveSupport::Concern

  included do
    belongs_to :operation, optional: true
    before_create { self.operation_id ||= Operations::Context.operation_id }
    attr_readonly :operation_id
  end

  def operation_origin? = operation_id.present?
end
