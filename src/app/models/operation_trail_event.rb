# Trilha do que o usuário de operação viu (14, R320; OPD7): ficha aberta, busca, "não encontrado" e exportação. Guardada por 12 meses (DOS1).
class OperationTrailEvent < ApplicationRecord
  include TenantScoped
  belongs_to :operation
  belongs_to :user
  belongs_to :customer, optional: true

  KINDS = %w[record_opened search not_found export].freeze
  KEEP_FOR = 12.months
end
