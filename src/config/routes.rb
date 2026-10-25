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
    # Crédito do contrato (11, R232b, R239): usar num título de acordo ou de estorno, e alocar o aguardando alocação.
    resources :credit_uses, path: "uso-de-credito", only: :create, module: :customers
    resources :credit_allocations, path: "alocacao-de-credito", only: :create, module: :customers
    # Direitos do titular (07): exportar (registra e abre a página com endereço assinado), anonimizar e reter.
    resource :data_export, path: "exportacao", only: %i[show create], module: :customers
    resource :anonymization, path: "anonimizacao", only: :create, module: :customers
    resource :retention, path: "retencao", only: %i[create destroy], module: :customers
    # Promessas abertas e pendentes na ficha (10, R203): o trecho do cabeçalho, refeito a cada evento.
    resources :promises, path: "promessas", only: :index, module: :customers
    # Acordos (11): o trecho da ficha, a simulação e a gravação da proposta.
    resources :agreement_simulations, path: "simulacao-de-acordo", only: %i[new create], module: :customers
    resources :agreements, path: "acordos", only: %i[index create], module: :customers
    # Acionamentos do cliente: histórico, campos que dependem da escolha e registro (04).
    resources :contact_attempts, path: "acionamentos", path_names: { new: "campos" }, only: %i[index new create], module: :customers
  end

  # Guarda de dados (07, R138): previsão dos próximos 30 dias, retidos e últimas execuções.
  resource :data_retention, path: "guarda-de-dados", only: :show

  # Histórico do título (05, R100) e divergências de valor (05, R99).
  resources :bills, path: "titulos", only: :show do
    # Memória de cálculo do valor atualizado (09, R174): carregada sob pedido pelo htmx.
    resource :calculation_memory, path: "memoria-de-calculo", only: :show, module: :bills
  end
  resources :value_discrepancies, path: "divergencias-de-valor", only: %i[index show] do
    resource :handling, path: "tratamento", only: :create, module: :value_discrepancies
  end

  # Promessas de pagamento (10): aprovar, recusar e cancelar (R192, R200) e a lista das pendentes (R204).
  resources :promises, path: "promessas", only: [] do
    get "pendentes", on: :collection, to: "promises/pendings#index", as: :pending
    resource :approval, path: "aprovacao", only: :create, module: :promises
    resource :refusal, path: "recusa", only: :create, module: :promises
    resource :cancellation, path: "cancelamento", only: :create, module: :promises
  end

  # Acordos (11): a lista, a página do acordo e, nela, aprovar, recusar, cancelar a proposta, o termo e o aceite (R216, R218 a R220).
  resources :agreements, path: "acordos", only: %i[index show] do
    get "pendentes", on: :collection, to: "agreements/pendings#index", as: :pending
    resource :approval, path: "aprovacao", only: :create, module: :agreements
    resource :refusal, path: "recusa", only: :create, module: :agreements
    resource :cancellation, path: "cancelamento", only: :create, module: :agreements
    resource :acceptance, path: "aceite", only: :create, module: :agreements
    resource :term, path: "termo", only: :show, module: :agreements
    # Depois do aceite: calcular a quitação antecipada (R230) e a quebra manual (R238).
    resource :settlement, path: "quitacao", only: :create, module: :agreements
    resource :break, path: "quebra", only: :create, module: :agreements
    # Reverter o acordo em dois passos (R239): abrir (create), concluir (update) e desistir (destroy).
    resource :reversion, path: "reversao", only: %i[create update destroy], module: :agreements
  end
  # Estornos à espera do gestor (R233, AH2): a lista e a decisão.
  resources :reversal_waits, path: "estornos-a-espera", only: %i[index update]
  # Arquivo de acordos (11, R244): exportar para o credor emitir os títulos; as exportações ficam registradas e os arquivos duram 30 dias.
  resources :agreement_exports, path: "arquivo-de-acordos", only: %i[index create show]

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
    resource :retention_period, path: "prazo-de-guarda", only: :update
    resource :portfolio, path: "carteira", only: %i[show update]
    resources :channels, path: "canais-de-recebimento", path_names: { new: "novo", edit: "editar" }, except: :show do
      resource :webhook_secret, path: "segredo-do-webhook", only: :create, module: :channels
    end
    resource :payment_policy, path: "politicas-de-pagamento", only: %i[show update]
    # Promessas (10): políticas do credor, prazo máximo do segmento e alçada por perfil (R189, R190, R206).
    resource :promises, path: "promessas-e-acordos", only: :show
    resource :promise_policy, path: "politicas-de-promessa", only: :update
    resource :promise_limits, path: "alcada-de-promessa", only: :update
    # Acordos (11, R207, R207a, R209): parâmetros do parcelamento e da mora, variáveis do segmento, limites por perfil e políticas. Gravam sem conferência do impacto.
    resource :agreement_parameters, path: "parametros-de-acordo", only: :update
    resource :agreement_policies, path: "politicas-de-acordo", only: :update
    resource :agreement_variables, path: "variaveis-de-acordo", only: :update
    resource :agreement_limits, path: "limites-de-acordo", only: :update
    # Segmentos do contrato (08): toda mudança passa pela conferência do impacto (R154) antes de valer.
    resources :segments, path: "segmentos", path_names: { new: "novo", edit: "editar" }, except: %i[show destroy] do
      resource :activation, path: "ativacao", only: %i[create destroy], module: :segments
      resource :movement, path: "movimento", only: :create, module: :segments
    end
    resource :segment_policy, path: "produto-do-contrato-no-segmento", only: :update
    # Parâmetros de encargos do credor e as políticas de encargos (09): também passam pela conferência do impacto.
    resource :charges, path: "encargos", only: :update
    resource :segment_confirmation, path: "confirmacao-dos-segmentos", only: :create
    # Índices do Banco Central (08): valores globais, correções do credor e "Buscar índices agora".
    resource :indexes, path: "indices", only: :show
    resources :index_adjustments, path: "correcoes-de-indices", only: %i[create destroy]
    resource :index_search, path: "busca-de-indices", only: :create
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
