# Controladores sem usuário do back office (página pública de pagamento, webhooks dos fornecedores): a requisição age como o sistema e declara
# o papel `crm_team` do banco (decisão 0024). Sem isto, o papel de entrada da aplicação não lê nem grava nada da carteira (falha fechada).
# Quem herda do ApplicationController já declara o papel do usuário; o teste de arquitetura confere que nenhum outro controlador fica sem.
module SystemDbRole
  extend ActiveSupport::Concern

  included do
    prepend_around_action { |_controller, action| Operations::Context.for_user(nil) { action.call } }
  end
end
