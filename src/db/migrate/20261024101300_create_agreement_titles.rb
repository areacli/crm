# Camada 15, etapas 3 e 4 (incremento 11): os títulos do acordo, a efetivação, o pagamento pelo número, a quebra e o arquivo de acordos. O título de acordo é um
# título da carteira (R225): ganha `kind` (comum, de acordo ou da quebra), o acordo a que pertence e a composição que herda dos originais (R224). Os componentes
# novos da baixa (encargos de atraso e juros do parcelamento, R227) entram na alocação e no abatimento. Índices: cada um diz a consulta que o usa (decisão 0010).
class CreateAgreementTitles < ActiveRecord::Migration[8.1]
  def change
    # Título de acordo (R224, R225): a entrada e as parcelas (`agreement`) e o título da quebra (`break`) pertencem a um acordo; o resto da carteira é `common`.
    # `composition` guarda, só nos títulos de acordo, de onde vêm os centavos (o original e o componente), os juros do parcelamento e os dias do período.
    change_table :bills do |t|
      t.string :kind, limit: 10, null: false, default: "common"
      t.references :agreement, foreign_key: { on_delete: :restrict }, index: false
      t.jsonb :composition
    end
    add_check_constraint :bills, "kind IN ('common', 'agreement', 'break') AND ((kind = 'common') = (agreement_id IS NULL))", name: "bills_kind"
    # Consulta: títulos de um acordo (página, efetivação, quebra, arquivo); só os títulos de acordo, a carga não escreve.
    add_index :bills, :agreement_id, where: "agreement_id IS NOT NULL", name: "index_bills_on_agreement"

    # Componentes novos da alocação e do abatimento (R227): encargos de atraso (`late`) e juros do parcelamento (`installment_interest`). O desconto pela
    # antecipação do pagamento (DA35) fica registrado como abatimento do tipo `early`.
    components = "'interest', 'fine', 'fees', 'correction', 'principal', 'late', 'installment_interest'"
    remove_check_constraint :payment_allocations, name: "payment_allocations_component"
    add_check_constraint :payment_allocations, "component IN (#{components})", name: "payment_allocations_component"
    remove_check_constraint :abatements, name: "abatements_valid"
    add_check_constraint :abatements, "kind IN ('creditor', 'tolerance', 'minimum', 'early') AND component IN (#{components}) AND amount_cents <> 0", name: "abatements_valid"
    change_column :payment_allocations, :component, :string, limit: 24
    change_column :abatements, :component, :string, limit: 24

    # Pagamento dirigido ao acordo (número sem sufixo, R230): sem título, como o pagamento de promessa. Consulta: pagamentos de um acordo (estorno e arquivo).
    add_reference :payments, :agreement, foreign_key: { on_delete: :restrict }, index: { where: "agreement_id IS NOT NULL" }

    # Crédito usado no acordo (R223): lançamento negativo no contrato de origem, ligado ao acordo; o cancelamento devolve com um lançamento positivo.
    add_reference :credits, :agreement, foreign_key: { on_delete: :restrict }, index: { where: "agreement_id IS NOT NULL" }

    # Promessa cancelada pelo aceite não deixa carência nos títulos (R235, 10 R188): foi substituída, não encerrada.
    add_column :payment_promises, :grace_free, :boolean, null: false, default: false

    change_table :agreements do |t|
      t.datetime :effectuated_at
      t.string :effectuated_by, limit: 12 # payment, acceptance ou credit (R225, R223)
      t.datetime :broken_at
      t.string :break_kind, limit: 20 # before_effectuation, after_effectuation ou manual (R234, R238)
      t.string :break_form, limit: 20 # installments_follow ou single_title (R236), a forma congelada no acordo
      t.boolean :broken_after_effectuation, null: false, default: false # marca "já quebrou acordo" (R248): sai só com a reativação (R236a)
      t.string :credit_mode, limit: 12 # down_payment ou rebate (R223)
      t.bigint :credit_down_cents, null: false, default: 0 # crédito usado como pagamento da entrada
      t.datetime :reactivated_at
    end
    add_check_constraint :agreements, "effectuated_by IS NULL OR effectuated_by IN ('payment', 'acceptance', 'credit')", name: "agreements_effectuated_by"
    add_check_constraint :agreements, "break_kind IS NULL OR break_kind IN ('before_effectuation', 'after_effectuation', 'manual')", name: "agreements_break_kind"
    # Consulta: tarefa diária da quebra (acordos em andamento do credor) e "já quebrou acordo" (segmentos, R248).
    add_index :agreements, %i[customer_id], where: "broken_after_effectuation", name: "index_agreements_broken_after_effectuation"

    # Cálculo da quitação antecipada (R230): vale até a data dele, e perde a validade quando o acordo recebe pagamento ou estorno depois dele.
    create_table :agreement_settlements do |t|
      t.references :agreement, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.date :on_date, null: false
      t.bigint :amount_cents, null: false
      t.jsonb :parts, null: false, default: {} # por título de acordo: o que a quitação cobra de cada componente
      t.datetime :expired_at
      t.datetime :created_at, null: false
    end

    # Arquivo de acordos (R244): cada exportação fica registrada (quem, quando, forma, quantas linhas); o arquivo é apagado em 30 dias.
    create_table :agreement_exports do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.string :form, limit: 10, null: false # news, full ou daily
      t.bigint :last_event_id, null: false, default: 0 # até onde os eventos foram levados ("novidades desde a última exportação")
      t.integer :lines, null: false, default: 0
      t.string :file_name, limit: 120
      t.datetime :downloaded_at
      t.datetime :created_at, null: false
      t.index %i[tenant_id created_at] # lista de exportações do credor e a limpeza dos arquivos com mais de 30 dias
    end
    add_check_constraint :agreement_exports, "form IN ('news', 'full', 'daily')", name: "agreement_exports_form"
  end
end
