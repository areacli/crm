Rails.application.routes.draw do
  resource :session

  # Estado de saúde para o balanceador e o monitoramento: 200 se a aplicação sobe sem exceção.
  get "up" => "rails/health#show", as: :rails_health_check

  root "summaries#show"

  # Nomes das rotas em inglês, caminhos em português (decisão 0013).
  resources :customers, path: "clientes", only: %i[index show]

  resources :imports, path: "importacoes", path_names: { new: "nova" }, only: %i[index new create show] do
    resource :confirmation, path: "confirmacao", only: :create, module: :imports
    resource :discard, path: "descarte", only: :create, module: :imports
    get "modelo", on: :collection, to: "imports/templates#show", as: :template
  end

  namespace :settings, path: "configuracao" do
    resource :portfolio, path: "carteira", only: %i[show update]
  end

  # Referência dos tokens e dos componentes: só onde se desenvolve e se testa.
  get "design-system" => "design_system#show", as: :design_system if Rails.env.local?
end
