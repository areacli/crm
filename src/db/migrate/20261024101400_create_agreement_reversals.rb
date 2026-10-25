# Camada 15, etapas 5 e 6 (incremento 11): estornos, reversão do acordo, crédito por estado e acordo sobre acordo. Cada índice diz a consulta que o usa (decisão 0010).
class CreateAgreementReversals < ActiveRecord::Migration[8.1]
  def change
    # Crédito por estado (11, R239, R233, dominio.md): o livro continua só de inserção e o saldo é a soma, agora por balde. `available` é o disponível; `awaiting` é o que
    # espera alocação (liquidação estornada na reversão, R239); `blocked` é o gerado por pagamento cujo estorno espera o gestor (AK2). Mudar de estado é um par de lançamentos.
    # `bill_id`: o título em que o crédito foi usado (a ficha, o acordo sobre acordo e o estorno da origem usam a ligação).
    change_table :credits do |t|
      t.string :bucket, limit: 10, null: false, default: "available"
      t.references :bill, foreign_key: { on_delete: :restrict }, index: { where: "bill_id IS NOT NULL" }
    end
    add_check_constraint :credits, "bucket IN ('available', 'awaiting', 'blocked')", name: "credits_bucket"
    # Consulta: saldo do contrato por estado (ficha, simulação, tarefa diária); o índice por contrato já existe e a tabela do contrato é pequena.
    add_index :credits, %i[contract_id bucket], name: "index_credits_on_contract_and_bucket"

    # Título de estorno (11, R233, AH1): título comum do cliente criado pelo CRM, numerado a partir do acordo de origem (`ACD-000001-E1`) e fora do acordo (`agreement_id` fica
    # vazio: nenhuma consulta do acordo o enxerga por engano). A carga e o batimento só leem `kind = 'common'`, então também não o atualizam nem o retiram (AI4).
    add_reference :bills, :origin_agreement, foreign_key: { to_table: :agreements, on_delete: :restrict }, index: { where: "origin_agreement_id IS NOT NULL" }
    remove_check_constraint :bills, name: "bills_kind"
    add_check_constraint :bills, "kind IN ('common', 'agreement', 'break', 'reversal') AND ((kind IN ('agreement', 'break')) = (agreement_id IS NOT NULL)) AND ((kind = 'reversal') = (origin_agreement_id IS NOT NULL))",
                         name: "bills_kind"

    # Reversão em dois passos (R239): a marca "em reversão" fica no acordo; o estado dele não muda até o cancelamento.
    change_table :agreements do |t|
      t.datetime :reversing_since
      t.string :reversal_reason, limit: 300
      t.references :reversal_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :reverted_at
    end

    # Estorno à espera do gestor (R233, AG1, AH2, AJ1): o efeito de estorno que a tabela fechada não resolve fica aqui, sem efeito, até a decisão.
    create_table :reversal_waits do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :payment, null: false, foreign_key: { on_delete: :restrict }, index: true
      t.references :agreement, foreign_key: { on_delete: :restrict }, index: { where: "agreement_id IS NOT NULL" }
      t.references :contract, null: false, foreign_key: true, index: false
      t.bigint :amount_cents, null: false
      t.string :reason, limit: 30, null: false # por que espera (chave do motivo)
      t.date :reversed_on, null: false # a data da ação de estorno (vale para o saldo)
      t.date :processed_on, null: false # o dia em que o estorno foi processado
      t.string :state, limit: 10, null: false, default: "waiting"
      t.string :decision, limit: 20
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :decided_at
      t.string :note, limit: 300
      t.jsonb :details, null: false, default: {} # o que o estorno tirou, por título e componente: a decisão "reabrir" usa
      t.datetime :created_at, null: false
      # Consulta: a lista do gestor (esperando, do mais antigo para o mais novo) e o número do menu.
      t.index %i[tenant_id state created_at], name: "index_reversal_waits_on_tenant_state"
    end
    add_check_constraint :reversal_waits, "state IN ('waiting', 'decided') AND amount_cents > 0 AND (decision IS NULL OR decision IN ('reopen', 'reversal_title', 'credit', 'revert'))", name: "reversal_waits_valid"
  end
end
