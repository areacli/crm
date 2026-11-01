module Segments
  # O catálogo da linguagem dos segmentos (13, R255 a R264; decisão 0023, seção 2): tudo o que um segmento pode ler, declarado uma vez. Dele saem o
  # editor (as listas agrupadas), a validação da árvore, a tradução para consulta (`Compiler`), o texto curto e a leitura por extenso (`Text`) e o
  # glossário. Atributo novo é mudança de especificação, não de configuração; nada aqui expõe dado que identifique a pessoa (R264).
  module Catalog
    # Comparações aceitas por tipo de valor (R254). `is` é o atributo sim/não, escrito sozinho ou negado.
    NUMERIC_OPS = %w[eq ne gt gte lt lte between].freeze
    CHOICE_OPS = %w[eq ne in].freeze
    OPS = { days: NUMERIC_OPS, count: NUMERIC_OPS, money: NUMERIC_OPS, percent: NUMERIC_OPS, option: CHOICE_OPS, text: CHOICE_OPS,
            reference: CHOICE_OPS, boolean: %w[is] }.freeze

    AGGREGATES = %w[count sum max min].freeze
    QUANTIFIERS = %w[some all none].freeze
    SUBJECTS = %w[contracts customers].freeze
    MAX_CONDITIONS = 20 # R287
    MAX_WINDOW_DAYS = 3650

    # Atributos do contrato com a definição da 08, R150 (os marcados "(hoje)" na 13, R255), mais "em atraso" e "atualizado".
    CONTRACT_ATTRIBUTES = {
      overdue_days: { type: :days },
      balance: { type: :money },
      overdue_percent: { type: :percent },
      age_days: { type: :days },
      person_type: { type: :option, options: %w[person company mixed] },
      product: { type: :text },
      product_largest: { type: :text },
      broke_agreement: { type: :boolean },
      in_arrears: { type: :boolean },
      updated_value: { type: :money }
    }.freeze

    # Atributos do cliente (R256): tipo pelo documento, há quantos dias entrou no CRM, maior atraso e saldo dos contratos dele no credor.
    CUSTOMER_ATTRIBUTES = {
      person_type: { type: :option, options: %w[person company] },
      customer_days: { type: :days },
      overdue_days: { type: :days },
      balance: { type: :money }
    }.freeze

    BILL_KINDS = %w[common agreement break reversal].freeze
    CONTACT_KINDS = %w[phone email address].freeze
    CONTACT_STATUSES = %w[valid invalid do_not_disturb].freeze
    CONTACT_ORIGINS = %w[load screen contact_attempt].freeze

    # Coleções (R258 a R261): campos que a condição sobre o item pode ler, qualificadores, campo principal do atalho entre aspas (SG14), se tem
    # data (janela "em N dias", R262) e o gênero da palavra (o editor e o texto concordam: "alguma promessa", "nenhum título").
    COLLECTIONS = {
      bills: {
        gender: :m,
        fields: { overdue_days: { type: :days }, balance: { type: :money }, amount: { type: :money }, product: { type: :text },
                  kind: { type: :option, options: BILL_KINDS } },
        qualifiers: %w[overdue due paid withdrawn renegotiated],
        main: :product, sums: %i[balance amount overdue_days]
      },
      contact_attempts: {
        gender: :m, dated: true,
        fields: { result: { type: :reference }, result_kind: { type: :option, options: ContactResult::KINDS.keys.map(&:to_s) },
                  channel: { type: :option, options: ContactAttempt::CHANNELS } },
        qualifiers: [], main: :result, sums: []
      },
      contacts: {
        gender: :m,
        fields: { status: { type: :option, options: CONTACT_STATUSES }, kind: { type: :option, options: CONTACT_KINDS },
                  origin: { type: :option, options: CONTACT_ORIGINS }, state: { type: :text }, city: { type: :text } },
        qualifiers: CONTACT_STATUSES, main: :status, sums: []
      },
      promises: {
        gender: :f, dated: true,
        fields: { state: { type: :option, options: PaymentPromise::STATES } },
        qualifiers: [], main: :state, sums: []
      },
      agreements: {
        gender: :m, dated: true,
        fields: { state: { type: :option, options: Agreement::STATES }, mode: { type: :option, options: Agreement::MODES } },
        qualifiers: [], main: :state, sums: []
      },
      payments: {
        gender: :m, dated: true,
        fields: { method: { type: :option, options: Payment.payment_methods.keys }, amount: { type: :money } },
        qualifiers: [], main: :method, sums: %i[amount]
      },
      contracts: {
        gender: :m,
        fields: CONTRACT_ATTRIBUTES.except(:person_type, :updated_value),
        qualifiers: %w[in_arrears], main: :product, sums: %i[balance overdue_days]
      },
      other_contracts: {
        gender: :m,
        fields: CONTRACT_ATTRIBUTES.except(:person_type, :updated_value),
        qualifiers: %w[in_arrears], main: :product, sums: %i[balance overdue_days]
      },
      customers: {
        gender: :m,
        fields: { person_type: { type: :option, options: %w[person company] } },
        qualifiers: [], main: :person_type, sums: []
      }
    }.freeze

    # Pais do contrato (R257): uma linha com o pai casa se algum cliente naquele papel atender. Do pai, os atributos do cliente e duas coleções.
    PARENTS = %w[holder responsible customer].freeze
    PARENT_COLLECTIONS = %w[contacts other_contracts].freeze

    # O que cada sujeito lê diretamente (R255, R256, R258 a R261).
    SUBJECT_COLLECTIONS = {
      "contracts" => %w[bills contact_attempts contacts promises agreements payments customers],
      "customers" => %w[contracts bills contact_attempts contacts promises agreements payments]
    }.freeze

    module_function

    def attributes_of(subject) = subject == "customers" ? CUSTOMER_ATTRIBUTES : CONTRACT_ATTRIBUTES

    def collection(key) = COLLECTIONS[key.to_sym]

    # O que um caminho quer dizer, para o sujeito: { kind: :attribute | :collection, parent:, name:, spec: } ou nil (fora do catálogo, R264).
    def resolve(subject, path)
      parts = path.to_s.split(".")
      return nil if parts.empty? || parts.size > 2

      if parts.size == 2
        parent, name = parts
        return nil unless subject == "contracts" && PARENTS.include?(parent)
        return { kind: :collection, parent: parent, name: name, spec: collection(name) } if PARENT_COLLECTIONS.include?(name)

        spec = CUSTOMER_ATTRIBUTES[name.to_sym]
        return spec && { kind: :attribute, parent: parent, name: name, spec: spec }
      end

      name = parts.first
      return { kind: :collection, parent: nil, name: name, spec: collection(name) } if SUBJECT_COLLECTIONS.fetch(subject, []).include?(name)

      spec = attributes_of(subject)[name.to_sym]
      spec && { kind: :attribute, parent: nil, name: name, spec: spec }
    end

    # Todos os caminhos do sujeito, na ordem do editor (R286): do sujeito, dos pais e as coleções.
    def paths(subject)
      own = attributes_of(subject).keys.map(&:to_s)
      parents = subject == "contracts" ? PARENTS.flat_map { |parent| CUSTOMER_ATTRIBUTES.keys.map { |name| "#{parent}.#{name}" } + PARENT_COLLECTIONS.map { |name| "#{parent}.#{name}" } } : []
      own + SUBJECT_COLLECTIONS.fetch(subject) + parents
    end
  end
end
