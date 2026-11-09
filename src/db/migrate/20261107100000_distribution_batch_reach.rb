# Lote de distribuição no alcance (14, R314): o resumo do lote traz códigos de contrato, documentos da planilha e saldo; a política de leitura
# do RLS deixa o usuário de operação ver só os que ele mesmo pediu.
class DistributionBatchReach < ActiveRecord::Migration[8.1]
  def up = Operations::Rls.install!(connection)

  def down
    execute("ALTER TABLE distribution_batches DISABLE ROW LEVEL SECURITY")
    %w[team_all operation_read operation_insert operation_update operation_delete].each { |policy| execute("DROP POLICY IF EXISTS #{policy} ON distribution_batches") }
  end
end
