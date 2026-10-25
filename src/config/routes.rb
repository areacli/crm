Rails.application.routes.draw do
  resource :session
  resource :password, path: "senha", only: %i[edit update]

  # Estado de saúde para o balanceador e o monitoramento: 200 se a aplicação sobe sem exceção.
  get "up" => "rails/health#show", as: :rails_health_check

  root "summaries#show"

  # Nomes das rotas em inglês, caminhos em português (decisão 0013).
  resources :customers, path: "clientes", only: %i[index show] do
    # Cadastro do cliente (06): nome corrigido na tela e contatos com a situação de cada um.
    resource :name, path: "nome", only: :update, module: :customers
    resources :contacts, path: "contatos", controller: "customer_contacts", only: %i[create update] do
      resource :status, path: "situacao", only: :update, controller: "customer_contacts/statuses"
    end
    # Transferência de crédito entre contratos do mesmo credor (R55a).
    resources :credit_transfers, path: "transferencias-de-credito", only: :create, module: :customers
    # Acionamentos do cliente: histórico, campos que dependem da escolha e registro (04).
    resources :contact_attempts, path: "acionamentos", path_names: { new: "campos" }, only: %i[index new create], module: :customers
  end

  # Histórico do título (05, R100) e divergências de valor (05, R99).
  resources :bills, path: "titulos", only: :show
  resources :value_discrepancies, path: "divergencias-de-valor", only: %i[index show] do
    resource :handling, path: "tratamento", only: :create, module: :value_discrepancies
  end

  # Lista de acionamentos dos credores (04, R78).
  resources :contact_attempts, path: "acionamentos", only: :index

  resources :imports, path: "importacoes", path_names: { new: "nova" }, only: %i[index new create show] do
    resource :confirmation, path: "confirmacao", only: :create, module: :imports
    resource :discard, path: "descarte", only: :create, module: :imports
    get "modelo", on: :collection, to: "imports/templates#show", as: :template
  end

  # Usuários (vínculos por credor), perfis e avisos do usuário.
  resources :memberships, path: "usuarios", path_names: { new: "novo" }, only: %i[index new create show update] do
    resource :profile, path: "perfil", only: :update, module: :memberships
    resource :activation, path: "ativacao", only: %i[create destroy], module: :memberships
    resource :password_reset, path: "redefinicao-de-senha", only: :create, module: :memberships
  end
  resources :profiles, path: "perfis", path_names: { new: "novo", edit: "editar" }, except: :show
  resources :notices, path: "avisos", only: %i[index update]
  namespace :notices, path: "avisos" do
    resource :reading, path: "leitura", only: :create
  end

  namespace :settings, path: "configuracao" do
    resource :tenant_registry, path: "dados-do-credor", only: %i[show update]
    resource :portfolio, path: "carteira", only: %i[show update]
    resources :channels, path: "canais-de-recebimento", path_names: { new: "novo", edit: "editar" }, except: :show do
      resource :webhook_secret, path: "segredo-do-webhook", only: :create, module: :channels
    end
    resource :payment_policy, path: "politicas-de-pagamento", only: %i[show update]
    resources :contact_results, path: "resultados-de-acionamento", path_names: { new: "novo", edit: "editar" }, except: %i[show destroy] do
      resource :activation, path: "ativacao", only: %i[create destroy], module: :contact_results
      resource :movement, path: "movimento", only: :create, module: :contact_results
    end
  end

  # Webhook de pagamento de um canal (sem sessão: a autenticação é a assinatura HMAC do corpo).
  post "webhooks/pagamentos/:channel_id", to: "webhooks/payments#create", as: :payments_webhook

  # Referência dos tokens e dos componentes: só onde se desenvolve e se testa.
  get "design-system" => "design_system#show", as: :design_system if Rails.env.local?
end
