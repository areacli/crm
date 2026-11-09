# Importações e arquivo de acordos sob o RLS (14, R313; decisão 0024): o resumo da conferência e o arquivo trazem dados do credor inteiro.
class ImportsAndExportsReach < ActiveRecord::Migration[8.1]
  def up = Operations::Rls.install!(connection)

  def down
    %w[imports agreement_exports].each do |table|
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      %w[team_all operation_read operation_insert operation_update operation_delete].each { |policy| execute("DROP POLICY IF EXISTS #{policy} ON #{table}") }
    end
  end
end
