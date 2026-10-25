Rails.application.routes.draw do
  resource :session
  resource :password, path: "senha", only: %i[edit update]

  # Estado de saúde para o balanceador e o monitoramento: 200 se a aplicação sobe sem exceção.
  get "up" => "rails/health#show", as: :rails_health_check

  root "summaries#show"

  # Nomes das rotas em inglês, caminhos em português (decisão 0013).
  resources :customers, path: "clientes", only: %i[index show] do
    # Transferência de crédito entre contratos do mesmo credor (R55a).
    resources :credit_transfers, path: "transferencias-de-credito", only: :create, module: :customers
  end

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
    resource :portfolio, path: "carteira", only: %i[show update]
    resources :channels, path: "canais-de-recebimento", path_names: { new: "novo", edit: "editar" }, except: :show do
      resource :webhook_secret, path: "segredo-do-webhook", only: :create, module: :channels
    end
    resource :payment_policy, path: "politicas-de-pagamento", only: %i[show update]
  end

  # Webhook de pagamento de um canal (sem sessão: a autenticação é a assinatura HMAC do corpo).
  post "webhooks/pagamentos/:channel_id", to: "webhooks/payments#create", as: :payments_webhook

  # Referência dos tokens e dos componentes: só onde se desenvolve e se testa.
  get "design-system" => "design_system#show", as: :design_system if Rails.env.local?
end
