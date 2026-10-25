# Histórico de alterações: só inserção (R8, R13, R14, R16, R18, R29).
class Change < ApplicationRecord
  include TenantScoped

  belongs_to :user, optional: true
  belongs_to :import, optional: true
end
