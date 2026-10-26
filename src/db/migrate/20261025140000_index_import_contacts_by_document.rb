# A confirmação em lotes (decisão 0021) lê os contatos dos clientes de cada lote por documento: o índice por importação sozinho obrigaria
# cada lote a percorrer todos os contatos da carga. O novo índice começa pela importação, então substitui o antigo. Custo na escrita: a
# preparação é gravada uma vez por carga e apagada ao fim (medido na V4-lote, no plano técnico da revisão).
class IndexImportContactsByDocument < ActiveRecord::Migration[8.1]
  def change
    remove_index :import_contacts, :import_id, name: "index_import_contacts_on_import_id"
    add_index :import_contacts, %i[import_id document], name: "index_import_contacts_on_import_id_and_document"
  end
end
