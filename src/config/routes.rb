Rails.application.routes.draw do
  resource :session, path: "sessao", path_names: { new: "nova", edit: "editar" }
  resource :password, path: "senha", path_names: { edit: "editar" }, only: %i[edit update]

  # Estado de saúde para o balanceador e o monitoramento: 200 se a aplicação sobe sem exceção.
  get "up" => "rails/health#show", as: :rails_health_check

  # SPA em EasyUI (decisão 0028): a casca fica na raiz, e o Resumo passa a `/resumo` (a aba fixa dela). O menu vem em JSON.
  root "shell#show"
  get "resumo", to: "summaries#show", as: :summary
  resource :menu, only: :show, defaults: { format: :json }

  # Confirmação curta de ações sem dados, no modal do painel (decisão 0022): o token assinado leva o título, a mensagem e o destino.
  get "confirmacao/:token", to: "confirmations#show", as: :confirmation, constraints: { token: %r{[^/]+} }, format: false

  # Nomes das rotas em inglês, caminhos em português (decisão 0013).
  resources :customers, path: "clientes", only: %i[index show] do
    # Cadastro do cliente (06): nome corrigido na tela e contatos com a situação de cada um.
    resource :name, path: "nome", path_names: { edit: "editar" }, only: %i[edit update], module: :customers
    # Linha do tempo da lateral (padrões de interface, revisão 24): o trecho que a ficha troca no filtro e na paginação (`data-trecho`).
    resource :timeline, path: "linha-do-tempo", only: :show, module: :customers
    resources :contacts, path: "contatos", path_names: { new: "novo", edit: "editar" }, controller: "customer_contacts", only: %i[new create edit update] do
      resource :status, path: "situacao", path_names: { new: "nova", edit: "editar" }, only: %i[edit update], controller: "customer_contacts/statuses"
    end
    # Transferência de crédito entre contratos do mesmo credor (R55a).
    resources :credit_transfers, path: "transferencias-de-credito", path_names: { new: "nova" }, only: %i[new create], module: :customers
    # Crédito do contrato (11, R232b, R239): usar num título de acordo ou de estorno, e alocar o aguardando alocação.
    resources :credit_uses, path: "uso-de-credito", path_names: { new: "novo" }, only: %i[new create], module: :customers
    resources :credit_allocations, path: "alocacao-de-credito", path_names: { new: "nova" }, only: %i[new create], module: :customers
    # Direitos do titular (07): exportar (registra e abre a página com endereço assinado), anonimizar e reter.
    resource :data_export, path: "exportacao", path_names: { new: "nova" }, only: %i[new show create], module: :customers
    resource :anonymization, path: "anonimizacao", path_names: { new: "nova" }, only: %i[new create], module: :customers
    resource :retention, path: "retencao", path_names: { new: "nova" }, only: %i[new create destroy], module: :customers
    # Promessas abertas e pendentes na ficha (10, R203): o trecho do cabeçalho, refeito a cada evento.
    resources :promises, path: "promessas", only: :index, module: :customers
    # Acordos (11): o trecho da ficha, a simulação e a gravação da proposta.
    resources :agreement_simulations, path: "simulacao-de-acordo", path_names: { new: "nova" }, only: %i[new create], module: :customers
    resources :agreements, path: "acordos", only: %i[index create], module: :customers
    # Acionamentos do cliente: histórico, campos que dependem da escolha e registro (04).
    resources :contact_attempts, path: "acionamentos", path_names: { new: "campos" }, only: %i[index new create], module: :customers do
      # Formulário de registro no painel (o `new` é o trecho dos campos que dependem da escolha).
      get "registrar", on: :collection, action: :form, as: :form
    end
  end

  # Guarda de dados (07, R138): previsão dos próximos 30 dias, retidos e últimas execuções.
  resource :data_retention, path: "guarda-de-dados", only: :show

  # Histórico do título (05, R100) e divergências de valor (05, R99).
  resources :bills, path: "titulos", only: :show
  resources :value_discrepancies, path: "divergencias-de-valor", only: %i[index show] do
    resource :handling, path: "tratamento", path_names: { new: "novo" }, only: %i[new create], module: :value_discrepancies
  end

  # Promessas de pagamento (10): aprovar, recusar e cancelar (R192, R200) e a lista das pendentes (R204).
  resources :promises, path: "promessas", only: [] do
    get "pendentes", on: :collection, to: "promises/pendings#index", as: :pending
    resource :approval, path: "aprovacao", only: :create, module: :promises
    resource :refusal, path: "recusa", path_names: { new: "nova" }, only: %i[new create], module: :promises
    resource :cancellation, path: "cancelamento", path_names: { new: "novo" }, only: %i[new create], module: :promises
  end

  # Acordos (11): a lista, a página do acordo e, nela, aprovar, recusar, cancelar a proposta, o termo e o aceite (R216, R218 a R220).
  resources :agreements, path: "acordos", only: %i[index show] do
    get "pendentes", on: :collection, to: "agreements/pendings#index", as: :pending
    resource :approval, path: "aprovacao", only: :create, module: :agreements
    resource :refusal, path: "recusa", path_names: { new: "nova" }, only: %i[new create], module: :agreements
    resource :cancellation, path: "cancelamento", path_names: { new: "novo" }, only: %i[new create], module: :agreements
    resource :acceptance, path: "aceite", path_names: { new: "novo" }, only: %i[new create], module: :agreements
    resource :term, path: "termo", only: :show, module: :agreements
    # Depois do aceite: calcular a quitação antecipada (R230) e a quebra manual (R238).
    resource :settlement, path: "quitacao", path_names: { new: "nova" }, only: %i[new create], module: :agreements
    resource :break, path: "quebra", path_names: { new: "nova" }, only: %i[new create], module: :agreements
    # Reverter o acordo em dois passos (R239): abrir (create), concluir (update) e desistir (destroy).
    resource :reversion, path: "reversao", path_names: { new: "nova" }, only: %i[new create update destroy], module: :agreements
  end
  # Estornos à espera do gestor (R233, AH2): a lista e a decisão.
  resources :reversal_waits, path: "estornos-a-espera", path_names: { edit: "decidir" }, only: %i[index edit update]
  # Arquivo de acordos (11, R244): exportar para o credor emitir os títulos; as exportações ficam registradas e os arquivos duram 30 dias.
  resources :agreement_exports, path: "arquivo-de-acordos", path_names: { new: "exportar" }, only: %i[index new create show]

  # Instrumentos de pagamento emitidos (12, R275): só leitura (dados em JSON, PDF do boleto e QR Code do Pix guardados aqui). Não há rota de emissão (R270).
  resources :payment_instruments, path: "instrumentos", only: :show do
    resource :pdf, only: :show, module: :payment_instruments
    resource :qr_code, path: "qrcode", only: :show, module: :payment_instruments
  end

  # Página pública de pagamento do cliente (12, parte C, R277 a R280): sem login, pelo token do link. Cartão só por checkout transparente; o boleto e o
  # Pix saem daqui, nunca do fornecedor. O token é qualquer texto sem barra: a página responde 404 igual para qualquer link que não sirva.
  constraints(token: %r{[^/]+}) do
    get "pagar/:token", to: "checkouts#show", as: :checkout, format: false
    scope "pagar/:token", module: :checkouts, as: :checkout, format: false do
      get "situacao", to: "situations#show", as: :situation
      get "parcelas", to: "installments#index", as: :installments
      post "cartao", to: "card_payments#create", as: :card_payment
      get "boleto.pdf", to: "boletos#show", as: :boleto
      get "qrcode.png", to: "qr_codes#show", as: :qr_code
    end
  end

  # Lista de acionamentos dos credores (04, R78).
  resources :contact_attempts, path: "acionamentos", only: :index

  resources :imports, path: "importacoes", path_names: { new: "nova" }, only: %i[index new create show] do
    resource :confirmation, path: "confirmacao", only: :create, module: :imports
    resource :discard, path: "descarte", only: :create, module: :imports
    resource :holds, path: "mudancas", only: %i[create destroy], module: :imports
    get "modelo", on: :collection, to: "imports/templates#show", as: :template
  end

  # Sistemas do credor (17, R396 a R399) e a política "Cadastro entre sistemas" (R410), que é do credor e não de um sistema: vem antes, para
  # o endereço não ser lido como o de um sistema.
  namespace :source_systems, path: "sistemas" do
    resource :customer_record_policy, path: "cadastro-entre-sistemas", only: :update
  end
  resources :source_systems, path: "sistemas", path_names: { new: "novo", edit: "editar" }, except: :show do
    resource :pause, path: "pausa", only: %i[create destroy], module: :source_systems
  end

  # Usuários (vínculos por credor), perfis e avisos do usuário.
  resources :memberships, path: "usuarios", path_names: { new: "novo", edit: "nome" }, only: %i[index new create show edit update] do
    resource :profile, path: "perfil", only: %i[edit update], module: :memberships
    resource :activation, path: "ativacao", only: %i[create destroy], module: :memberships
    resource :password_reset, path: "redefinicao-de-senha", only: :create, module: :memberships
  end
  resources :profiles, path: "perfis", path_names: { new: "novo", edit: "editar" }, except: :show
  resources :notices, path: "avisos", only: %i[index update]
  namespace :notices, path: "avisos" do
    resource :reading, path: "leitura", only: :create
  end

  # Distribuição (14, R311, R317, R326): à mão, mudar e recolher; o lote e o enquadramento da distribuição vêm a seguir.
  resources :distributions, path: "distribuicao", path_names: { new: "nova", edit: "editar" }, only: %i[index new create edit update] do
    resource :recall, path: "recolher", only: %i[new create], module: :distributions
  end

  resources :distribution_batches, path: "distribuicao/lotes", path_names: { new: "novo" }, only: %i[new create show] do
    member do
      post :confirm, path: "confirmar"
      delete :discard, path: "descartar"
    end
  end

  # Pessoas da operação (14, R310, R310a): o gestor da operação cuida das pessoas dela e, onde o credor deixa, dá vínculos.
  resources :operation_people, path: "operacao/pessoas", path_names: { new: "nova" }, only: %i[index new create update] do
    resources :links, path: "vinculos", path_names: { new: "novo" }, only: %i[new create], controller: "operation_links"
  end

  namespace :settings, path: "configuracao" do
    resource :tenant_registry, path: "dados-do-credor", only: %i[show update]
    resource :retention_period, path: "prazo-de-guarda", only: :update
    resource :portfolio, path: "carteira", only: %i[show update]
    # Métodos de recebimento (16, R373; antes "canais de recebimento"): uma tela só, com as integrações no detalhe de cada método.
    resources :channels, path: "metodos-de-recebimento", path_names: { new: "novo", edit: "editar" }, except: :show do
      resource :webhook_secret, path: "segredo-do-webhook", only: :create, module: :channels
    end
    resource :payment_policy, path: "politicas-de-pagamento", only: %i[show update]
    # Integrações (12, "contas de pagamento"): fornecedor de boleto, Pix e cartão por meio de pagamento e ambiente. A lista é o detalhe de cada
    # método de recebimento (16, R373): não há página própria.
    resources :payment_accounts, path: "integracoes", path_names: { new: "nova", edit: "editar" }, except: %i[index show] do
      resource :activation, path: "ativacao", only: %i[create destroy], module: :payment_accounts
      resource :webhook_secret, path: "segredo-do-webhook", only: :create, module: :payment_accounts
      resource :connection_test, path: "teste-de-conexao", only: :create, module: :payment_accounts
    end
    # Promessas (10): políticas do credor, prazo máximo do segmento e alçada por perfil (R189, R190, R206).
    resource :promises, path: "promessas-e-acordos", only: :show
    resource :promise_policy, path: "politicas-de-promessa", only: :update
    resource :promise_limits, path: "alcada-de-promessa", only: :update
    # Acordos (11, R207, R207a, R209): parâmetros do parcelamento e da mora, variáveis do item do enquadramento, limites por perfil e políticas. As variáveis passam pela
    # conferência do impacto (13, R272); o resto grava direto.
    resource :agreement_parameters, path: "parametros-de-acordo", only: :update
    resource :agreement_policies, path: "politicas-de-acordo", only: :update
    resource :agreement_variables, path: "variaveis-de-acordo", only: :update
    resource :agreement_limits, path: "limites-de-acordo", only: :update
    # Segmentos (13): filtros nomeados do credor, com o editor em blocos, "Conferir" e o glossário da linguagem. Mudar um segmento usado no
    # enquadramento passa pela conferência do impacto (R272, R273).
    get "segmentos/glossario", to: "segment_glossaries#show", as: :segment_glossary
    resources :segments, path: "segmentos", path_names: { new: "novo", edit: "editar" } do
      collection do
        post :draft, path: "rascunho"
        post :probe, path: "conferir"
        get "conferir/:probe_id", action: :probe_result, as: :probe_result
      end
      resource :activation, path: "ativacao", only: %i[create destroy], module: :segments
    end
    # Enquadramento financeiro (13, R265 a R272): itens em ordem com as regras de encargos, promessa e acordo; toda mudança passa pela
    # conferência do impacto antes de valer.
    resources :tiers, path: "enquadramento-financeiro", path_names: { new: "incluir", edit: "regras" }, except: :show do
      resource :movement, path: "movimento", only: :create, module: :tiers
    end
    # Parâmetros de encargos do credor e as políticas de encargos (09): também passam pela conferência do impacto.
    resource :charges, path: "encargos", only: :update
    resource :tier_confirmation, path: "confirmacao-do-enquadramento", only: :create
    resources :tier_reviews, path: "conferencias-do-enquadramento", only: :show
    # Índices do Banco Central (08): valores globais, correções do credor e "Buscar índices agora".
    resource :indexes, path: "indices", only: :show
    resources :index_adjustments, path: "correcoes-de-indices", path_names: { new: "nova" }, only: %i[new create destroy]
    resource :index_search, path: "busca-de-indices", only: :create
    resources :contact_results, path: "resultados-de-acionamento", path_names: { new: "novo", edit: "editar" }, except: %i[show destroy] do
      resource :activation, path: "ativacao", only: %i[create destroy], module: :contact_results
      resource :movement, path: "movimento", only: :create, module: :contact_results
    end
  end

  # Filas de trabalho (15): o "Próximo" e o "Devolver" do operador (permissão 7); a visão das filas, a configuração dos enquadramentos e dos
  # grupos e a estratégia de cada operador (permissão 21). As rotas fixas vêm antes da ficha de uma fila (`/filas/:id`).
  post "fila/proximo", to: "queue_deliveries#create", as: :next_delivery
  delete "fila/entrega", to: "queue_deliveries#destroy", as: :current_delivery
  scope "filas", as: :queues do
    resources :work_queues, path: "enquadramento", module: :settings, path_names: { new: "incluir", edit: "editar" }, only: %i[index new create edit update destroy] do
      member { post :move, path: "mover" }
      collection do
        get :review, path: "conferencia", action: :review_show
        post :confirm, path: "confirmar"
      end
    end
    resources :queue_settings, path: "ajustes", module: :settings, path_names: { edit: "editar" }, only: %i[edit update]
    resources :queue_groups, path: "grupos", module: :settings, path_names: { new: "novo", edit: "editar" }, only: %i[index new create edit update destroy]
    resources :queue_strategies, path: "estrategias", module: :settings, path_names: { edit: "editar" }, only: %i[edit update]
    resources :releases, path: "entregas", module: :queue_boards, only: [] do
      member { post :create, path: "liberar" }
    end
    get "", to: "queue_boards#index", as: :board
    get ":id", to: "queue_boards#show", as: :board_queue, constraints: { id: /\d+/ }
  end

  # Operações (14; padrões de interface, revisões 22 e 30): área própria do menu, no grupo "Distribuição do trabalho", fora da configuração. Os controladores seguem no módulo
  # Settings; as rotas da trilha e do enquadramento vêm antes das do credenciamento, que usa `/operacoes/:id`.
  scope "operacoes", module: :settings, as: :settings do
    # Enquadramento da distribuição (14, R342 a R347): itens por posição; cada mudança vai à conferência do impacto antes de valer.
    resources :distribution_rules, path: "enquadramento-da-distribuicao", path_names: { new: "incluir", edit: "editar" }, only: %i[index new create edit update destroy] do
      member { post :move, path: "mover" }
      collection do
        get :review, path: "conferencia", action: :review_show
        post :confirm, path: "confirmar"
      end
    end
    resource :operation_policies, path: "politicas", only: :update
    resources :operation_trails, path: "trilha", only: :index
    # Operações credenciadas (14, R306, R307, R310): a ficha é a do credenciamento; situação e vínculos no painel.
    resources :operations, path: "", path_names: { new: "credenciar" }, only: %i[index new create show] do
      resource :status, path: "situacao", path_names: { new: "nova", edit: "editar" }, only: %i[new create], module: :operations
      resources :links, path: "vinculos", path_names: { new: "novo" }, only: %i[new create destroy], module: :operations
    end
  end

  # Webhook de pagamento de um canal (sem sessão: a autenticação é a assinatura HMAC do corpo).
  post "webhooks/pagamentos/:channel_id", to: "webhooks/payments#create", as: :payments_webhook

  # Aviso de um fornecedor de instrumentos de pagamento (12, parte D): uma rota por conta de pagamento. O Pix da Efí acrescenta `/pix` à URL registrada.
  post "webhooks/pagamentos/contas/:conta(/pix)", to: "webhooks/payment_accounts#create", as: :payment_account_webhook, format: false, constraints: { conta: /\d+/ }

  # Páginas de erro (config.exceptions_app): o Rails reenvia a requisição para /<código> quando uma exceção ou um status de erro sai.
  match "/:status", to: "errors#show", via: :all, constraints: { status: /400|403|404|406|422|429|500|503/ }, as: :error

  # Referência dos tokens e dos componentes: só onde se desenvolve e se testa.
  if Rails.env.local?
    get "design-system" => "design_system#show", as: :design_system
    # Exemplos da SPA (decisão 0028): espera, falha, cálculo à vista, edição inline, janela e diálogo, com respostas de mentira.
    scope "design-system", controller: :design_system, as: :design_system do
      post "calculo"
      patch "inline"
      get "lento"
      get "janela"
      get "dialogo"
      post "dialogo", action: :gravar_dialogo
    end
  end
end
