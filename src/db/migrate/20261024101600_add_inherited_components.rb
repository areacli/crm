# Acordo sobre acordo (11, R250): os juros do parcelamento e os encargos de atraso de um título de acordo viram componentes herdados próprios do título novo, com teto de desconto
# próprio (padrão 0%). Entram na alocação e no abatimento, depois dos juros e antes da multa na ordem da R224.
class AddInheritedComponents < ActiveRecord::Migration[8.1]
  COMPONENTS = "'interest', 'fine', 'fees', 'correction', 'principal', 'late', 'installment_interest', 'inherited_installment_interest', 'inherited_late'".freeze

  def up
    remove_check_constraint :payment_allocations, name: "payment_allocations_component"
    add_check_constraint :payment_allocations, "component IN (#{COMPONENTS})", name: "payment_allocations_component"
    remove_check_constraint :abatements, name: "abatements_valid"
    add_check_constraint :abatements, "kind IN ('creditor', 'tolerance', 'minimum', 'early') AND component IN (#{COMPONENTS}) AND amount_cents <> 0", name: "abatements_valid"
    change_column :payment_allocations, :component, :string, limit: 40
    change_column :abatements, :component, :string, limit: 40
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
