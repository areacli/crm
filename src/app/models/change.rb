# Histórico de alterações: só inserção (R8, R13, R14, R16, R18, R29, R116). `origin` diz de onde veio a mudança de cadastro (load, screen,
# contact_attempt) e `note` guarda o motivo digitado.
class Change < ApplicationRecord
  include TenantScoped

  belongs_to :user, optional: true
  belongs_to :import, optional: true
end
