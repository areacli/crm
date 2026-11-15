module Cadences
  # O catálogo fixo da régua (21, R429 e R433): os marcos, com o sujeito, o objeto e as colunas que cada um aceita, e os tipos de ação, com o
  # parâmetro de cada um. Marco novo é atributo novo do catálogo da 13; tipo novo é mudança de especificação. O parâmetro diz o que se quer, não
  # como se faz (a régua só enfileira).
  module Catalog
    # Marco => sujeito, objeto (o sujeito, ou contrato × fatura) e a menor coluna aceita (nil: qualquer, de −365 a 3.650).
    MILESTONES = {
      "bill_due" => { subject: "contracts", object: "bill", min_offset: nil },
      "contract_arrears" => { subject: "contracts", object: "subject", min_offset: 1 },
      "customer_arrears" => { subject: "customers", object: "subject", min_offset: 1 },
      "contract_in_collection" => { subject: "contracts", object: "subject", min_offset: 0 },
      "customer_in_collection" => { subject: "customers", object: "subject", min_offset: 0 },
      "contract_start" => { subject: "contracts", object: "subject", min_offset: nil },
      "contract_creation" => { subject: "contracts", object: "subject", min_offset: 0 },
      "customer_registration" => { subject: "customers", object: "subject", min_offset: 0 }
    }.freeze

    MIN_OFFSET = -365
    MAX_OFFSET = 3650

    # Comunicações: o parâmetro é a peça do canal. O destinatário sai do sujeito (R436).
    COMMUNICATIONS = { "sms" => "sms", "email" => "email", "whatsapp" => "whatsapp", "letter" => "letter" }.freeze
    MEASURES = %w[negativation protest lawsuit credit_suspension].freeze
    KINDS = (COMMUNICATIONS.keys + %w[issue_instrument proposal promise task] + MEASURES).freeze

    # Proposta de acordo: forma × concessão (RED3); promessa: o valor, no prazo máximo do item financeiro.
    PROPOSAL_FORMS = %w[cash installments].freeze
    PROPOSAL_CONCESSIONS = %w[max min none].freeze
    PROMISE_VALUES = %w[total_open overdue_only].freeze
    # Emissão (Q4): fora do marco "vencimento da fatura", o objeto é um destes; no marco da fatura, é a própria fatura.
    ISSUE_OBJECTS = %w[overdue_bills agreement_bills promise].freeze
    MAX_DUE_DAYS = 60

    # Prazo de retorno padrão, em horas, contado da entrada na fila (R437a); a régua pode trocar por tipo.
    RETURN_HOURS = { "sms" => 24, "email" => 24, "whatsapp" => 24, "letter" => 72, "issue_instrument" => 1, "proposal" => 24, "promise" => 24,
                     "task" => 24, "negativation" => 72, "protest" => 72, "lawsuit" => 72, "credit_suspension" => 72 }.freeze

    module_function

    def subject_of(milestone) = MILESTONES.fetch(milestone.to_s)[:subject]
    def bill_object?(milestone) = MILESTONES.fetch(milestone.to_s)[:object] == "bill"
    def min_offset(milestone) = MILESTONES.fetch(milestone.to_s)[:min_offset] || MIN_OFFSET
    def communication?(kind) = COMMUNICATIONS.key?(kind.to_s)
    def measure?(kind) = MEASURES.include?(kind.to_s)
    def return_hours(cadence, kind) = (cadence.return_hours || {}).fetch(kind.to_s, RETURN_HOURS.fetch(kind.to_s)).to_i

    # Os meios que a régua pode emitir no credor (16, R377): boleto e Pix com integração ativa em produção. O link de cartão não sai pela régua
    # nesta versão (plano técnico da camada 23, decisão 6): ele é da parte C da camada 20.
    RULE_METHODS = %w[boleto pix].freeze

    def issuable_methods(tenant)
      kinds = tenant.payment_accounts.active.where(environment: "production").distinct.pluck(:modality)
      PaymentMethod::ISSUABLE.slice(*RULE_METHODS).select { |_, kind| kinds.include?(kind) }.keys
    end
  end
end
