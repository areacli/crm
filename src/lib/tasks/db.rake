# O esquema do Rails (schema.rb) não representa tabela sem registro de escrita: depois de carregar o esquema (banco novo, testes, produção
# que sobe do zero), a tabela de preparação da importação volta a ser `unlogged`, como na migração (decisão 0004).
Rake::Task["db:schema:load"].enhance do
  ActiveRecord::Base.connection.execute("ALTER TABLE IF EXISTS import_rows SET UNLOGGED")
end
