# Camada 15, etapa 2 (incremento 11): a proposta de acordo por novação. Limites por perfil (R209), o acordo e os títulos que ele prende (R211, R218), o
# registro dos eventos (fonte do histórico da ficha e do arquivo de acordos, R244). O acordo guarda congelado tudo o que é dele (R210) em `terms`.
# Índices: cada um diz a consulta que o usa (decisão 0010); o custo na escrita está no plano técnico da camada.
class CreateAgreements < ActiveRecord::Migration[8.1]
  STATES = %w[pending approved refused not_approved expired canceled awaiting_effectuation active_on_time active_late settled broken renegotiated].freeze

  def change
    # Limites do perfil por segmento, dentro das variáveis dele (R209): nascem com o segmento e com o perfil (padrão da DA4).
    create_table :agreement_limits do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :profile, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.jsonb :caps, null: false, default: { "installment" => {}, "cash" => {} }
      t.integer :max_installments, null: false
      t.integer :min_down_payment_pct, null: false
      t.bigint :ceiling_discount_cents # teto opcional em reais do desconto total (N23); vazio, sem teto
      t.bigint :ceiling_value_cents    # teto opcional em reais do valor líquido do acordo (N23)
      t.index %i[segment_id profile_id], unique: true
    end
    add_check_constraint :agreement_limits, "max_installments BETWEEN 1 AND 120 AND min_down_payment_pct BETWEEN 1 AND 100 AND " \
                                            "(ceiling_discount_cents IS NULL OR ceiling_discount_cents >= 0) AND (ceiling_value_cents IS NULL OR ceiling_value_cents >= 0)",
                         name: "agreement_limits_valid"
    # Segmentos e perfis que já existem recebem os limites padrão (R207, R209), como um segmento novo: os segmentos nascem sem desconto, então a metade é igual.
    reversible do |direction|
      direction.up do
        execute <<~SQL
          insert into agreement_limits (segment_id, profile_id, caps, max_installments, min_down_payment_pct)
          select s.id, p.id, s.agreement_caps, case when p.permissions ? 'change_financial_policies' then s.agreement_max_installments else greatest(s.agreement_max_installments / 2, 1) end,
                 s.agreement_min_down_payment_pct
          from segments s join profiles p on p.tenant_id = s.tenant_id
        SQL
      end
    end

    create_table :agreements do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: { on_delete: :restrict }
      t.references :segment, foreign_key: { on_delete: :nullify }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false        # quem montou
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false # quem aprovou ou recusou
      t.string :number, limit: 20, null: false
      t.string :state, limit: 24, null: false
      t.string :mode, limit: 12, null: false # "cash" (à vista) ou "installments" (parcelado)
      t.date :built_on, null: false           # dia da montagem (dia zero da validade e data-base dos valores)
      t.date :valid_until, null: false
      t.jsonb :discounts, null: false, default: {} # percentual de desconto por componente (igual para todos os títulos)
      t.bigint :base_cents, null: false
      t.bigint :discount_cents, null: false
      t.bigint :value_cents, null: false       # valor do acordo: base menos descontos
      t.bigint :credit_cents, null: false, default: 0 # crédito usado como abatimento (etapa 3)
      t.bigint :net_cents, null: false         # valor líquido: o que o acordo cobra, sem os juros do parcelamento
      t.bigint :down_payment_cents, null: false
      t.date :down_payment_due, null: false
      t.integer :installments_count, null: false, default: 0
      t.integer :installment_day
      t.string :installment_method, limit: 10, null: false, default: "none"
      t.decimal :rate_pct, precision: 7, scale: 4, null: false, default: 0
      t.decimal :effective_annual_pct, precision: 9, scale: 4, null: false, default: 0
      t.bigint :total_cents, null: false      # soma total a pagar: entrada mais parcelas, com os juros do parcelamento (R219)
      t.bigint :interest_cents, null: false, default: 0
      t.jsonb :schedule, null: false, default: [] # entrada e parcelas: número, vencimento, valor, juros do parcelamento, amortização e saldo
      t.jsonb :terms, null: false, default: {}    # tudo o que o acordo congela (R210): variáveis, parâmetros, limites, políticas, praça, avisos
      t.datetime :decided_at                   # aprovação ou recusa (a aprovada pela alçada, na montagem)
      t.string :reason, limit: 300             # motivo da recusa, do cancelamento ou da substituição
      t.datetime :closed_at
      t.bigint :replaced_by_id
      # Aceite (R220, R220a): o termo foi apresentado (canal e momento), o canal e o momento do aceite, o comprovante e quem aceitou e registrou.
      t.string :presented_channel, limit: 12
      t.datetime :presented_at
      t.string :accepted_channel, limit: 12
      t.datetime :accepted_at
      t.string :proof, limit: 200
      t.references :accepted_by_customer, foreign_key: { to_table: :customers, on_delete: :nullify }, index: false
      t.string :accepted_role, limit: 24
      t.references :registered_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :registered_at
      t.jsonb :term_snapshot, null: false, default: {} # o termo guardado como estava no aceite, sem edição (R220)
      t.timestamps
      t.index %i[tenant_id number], unique: true      # acordo pelo número, na confirmação de pagamentos
      t.index %i[tenant_id state valid_until]         # tarefa diária (expira) e lista de acordos por situação
      t.index %i[tenant_id created_at]                # lista de acordos por período
    end
    add_check_constraint :agreements, "state IN (#{STATES.map { |state| "'#{state}'" }.join(', ')})", name: "agreements_state"
    add_check_constraint :agreements, "mode IN ('cash', 'installments') AND installment_method IN ('none', 'price', 'sac') AND installments_count >= 0 AND " \
                                      "base_cents > 0 AND discount_cents >= 0 AND value_cents > 0 AND net_cents > 0 AND down_payment_cents > 0 AND down_payment_cents <= net_cents",
                         name: "agreements_valid"

    # Os títulos do acordo (R211): a base e o desconto de cada um por componente (a linha "dívida" do arquivo) e o valor dele no acordo. `held` prende o
    # título enquanto a proposta vale ou o acordo não terminou (R218): um título numa proposta vigente só.
    create_table :agreement_bills do |t|
      t.references :agreement, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :bill, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.references :contract, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.jsonb :base, null: false, default: {}      # valor atualizado do título na montagem, por componente
      t.jsonb :discount, null: false, default: {}  # desconto por componente
      t.jsonb :credit, null: false, default: {}    # crédito usado como abatimento, por componente (etapa 3)
      t.bigint :value_cents, null: false           # valor do título no acordo
      t.bigint :amount_cents, null: false          # valor vigente do título na montagem (conferido no aceite, R220)
      t.bigint :paid_cents, null: false            # principal já pago na montagem (conferido no aceite, R220)
      t.boolean :held, null: false, default: true
      t.index :bill_id, unique: true, where: "held", name: "index_agreement_bills_held_bill" # título preso a uma proposta ou acordo só (R218)
      t.index :bill_id
    end

    create_table :agreement_events do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :agreement, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.string :kind, limit: 30, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.index %i[tenant_id occurred_at] # eventos do dia para o arquivo (etapa 3)
    end
  end
end
