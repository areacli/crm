# Camada 15, etapa 1 (incremento 11, fundação dos acordos por novação): parâmetros do parcelamento e da mora do título de acordo com override
# no segmento (R207a), variáveis de acordo do segmento (R207), políticas e tolerâncias do credor (R228a), municípios do IBGE e feriados da praça
# (R249), estado final do pagamento e abatimentos (R226, N1, R228a). Índices: cada um diz a consulta que o usa (decisão 0010).
class CreateAgreementFoundation < ActiveRecord::Migration[8.1]
  def change
    # Parâmetros de encargos do credor que só o acordo usa (R207a): taxa e método do parcelamento, convenção de dias e base da multa dos títulos de
    # acordo. O segmento herda do credor quando o campo dele é vazio. Mudar estes campos não muda título nenhum (os acordos congelam os seus).
    change_table :tenant_settings do |t|
      t.decimal :installment_rate_pct, precision: 7, scale: 4, null: false, default: 0
      t.string :installment_method, limit: 10, null: false, default: "none"
      t.string :agreement_days_convention, limit: 10, null: false, default: "thirty"
      t.string :agreement_fine_base, limit: 10, null: false, default: "corrected"
      # As políticas do acordo e as tolerâncias de valor (R228a), com o esquema, as opções e o padrão em `Agreements::Policies`. Só guarda o que
      # o credor escolheu; o que falta vale o padrão. Número do acordo: sequência por credor (R210, ACD-000123).
      t.jsonb :agreement_policies, null: false, default: {}
      t.integer :agreement_sequence, null: false, default: 0
    end
    add_check_constraint :tenant_settings, "installment_rate_pct BETWEEN 0 AND 100 AND installment_method IN ('none', 'price', 'sac') AND " \
                                           "agreement_days_convention IN ('calendar', 'thirty') AND agreement_fine_base IN ('corrected', 'face')",
                         name: "tenant_settings_agreement_params"

    change_table :segments do |t|
      t.decimal :installment_rate_pct, precision: 7, scale: 4
      t.string :installment_method, limit: 10
      t.string :agreement_days_convention, limit: 10
      t.string :agreement_fine_base, limit: 10
      # Variáveis de acordo do segmento (R207): teto de desconto por componente, em duas colunas (parcelado e à vista), e as demais.
      t.jsonb :agreement_caps, null: false, default: { "installment" => {}, "cash" => {} }
      t.integer :agreement_max_installments, null: false, default: 12
      t.bigint :agreement_min_installment_cents, null: false, default: 5_000
      t.integer :agreement_min_down_payment_pct, null: false, default: 10
      t.integer :agreement_down_payment_days, null: false, default: 10
      t.integer :agreement_validity_days, null: false, default: 5
      t.integer :agreement_tolerance_days, null: false, default: 3
      t.integer :agreement_break_days, null: false, default: 30
    end
    add_check_constraint :segments, "(installment_rate_pct IS NULL OR installment_rate_pct BETWEEN 0 AND 100) AND (installment_method IS NULL OR installment_method IN ('none', 'price', 'sac')) AND " \
                                    "(agreement_days_convention IS NULL OR agreement_days_convention IN ('calendar', 'thirty')) AND (agreement_fine_base IS NULL OR agreement_fine_base IN ('corrected', 'face'))",
                         name: "segments_agreement_params"
    add_check_constraint :segments, "agreement_max_installments BETWEEN 1 AND 120 AND agreement_min_installment_cents >= 0 AND agreement_min_down_payment_pct BETWEEN 1 AND 100 AND " \
                                    "agreement_down_payment_days BETWEEN 1 AND 365 AND agreement_validity_days BETWEEN 1 AND 365 AND agreement_tolerance_days BETWEEN 0 AND 60 AND agreement_break_days BETWEEN 1 AND 365",
                         name: "segments_agreement_variables"

    # Municípios do IBGE (R249, M12): a lista que a praça do devedor usa, importada pelo administrador. Nome sem acento e em minúsculas na chave.
    create_table :municipalities do |t|
      t.string :ibge_code, limit: 7, null: false
      t.string :name, limit: 120, null: false
      t.string :name_key, limit: 120, null: false
      t.string :state, limit: 2, null: false
      t.index :ibge_code, unique: true
      t.index %i[state name_key], unique: true # casa o endereço do cliente com o município (nome sem acento e UF)
    end

    # Feriados estaduais (sem município) e municipais, importados pelo administrador (R249). Os nacionais são calculados (`Charges::BusinessDays`).
    create_table :holidays do |t|
      t.string :state, limit: 2, null: false
      t.references :municipality, foreign_key: { on_delete: :cascade }, index: false
      t.date :date, null: false
      t.string :name, limit: 150, null: false
      t.index %i[state municipality_id date], unique: true, nulls_not_distinct: true # a praça lê os feriados do município e do estado dele
      t.index :date
    end

    # Estado final do pagamento (PG-3, R226): coluna opcional do arquivo. "settled" (quitado) dá o título por pago; "partial" é só informativo.
    add_column :payment_rows, :final_state, :string, limit: 10
    add_column :payments, :final_state, :string, limit: 10

    # Abatimentos (R226, R228a, R229): a diferença dada por paga pelo credor ("creditor"), por tolerância de valor ("tolerance") ou por mínimo
    # ("minimum"), por componente. Só inserção: o estorno do pagamento grava as linhas negativas. Consulta: abatimentos do pagamento no estorno.
    create_table :abatements do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :payment, null: false, foreign_key: true, index: true
      t.references :bill, null: false, foreign_key: true, index: false
      t.string :kind, limit: 10, null: false
      t.string :component, limit: 12, null: false
      t.bigint :amount_cents, null: false
      t.datetime :created_at, null: false
      t.index %i[tenant_id created_at] # painel dos abatimentos (R242, etapa 5)
    end
    add_check_constraint :abatements, "kind IN ('creditor', 'tolerance', 'minimum') AND component IN ('interest', 'fine', 'fees', 'correction', 'principal') AND amount_cents <> 0",
                         name: "abatements_valid"
  end
end
