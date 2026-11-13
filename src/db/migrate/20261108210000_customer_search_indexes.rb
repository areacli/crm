# Índices da busca da lista de clientes (plano técnico da lista de clientes com 200 mil, decisão 0010, opção B escolhida pelo Paulo em 08/11/2026): o nome em
# trigramas, na mesma expressão da busca (`Portfolio::Query#search_by`), e o prefixo do documento. `pg_trgm` é extensão confiável: o dono do banco a cria sem superusuário.
class CustomerSearchIndexes < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    add_index :customers, "translate(lower(name), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') gin_trgm_ops", using: :gin, name: "index_customers_on_folded_name_trgm"
    add_index :customers, :document, opclass: :varchar_pattern_ops, name: "index_customers_on_document_prefix"
  end
end
