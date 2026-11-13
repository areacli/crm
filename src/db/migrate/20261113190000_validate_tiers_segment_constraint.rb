# A restrição `tiers_segment_unless_catch_all` (só o item padrão do enquadramento fica sem segmento) nasceu sem validar as linhas que já existiam
# (`20261030100000`), porque a base da demonstração ainda tinha os segmentos antigos, e nunca foi validada depois. O banco criado migração a migração
# ficou com ela "não validada", diferente do `schema.rb` e dos bancos criados a partir dele. As linhas antigas saíram na recriação da demonstração e
# toda linha nova já era conferida: validar agora só alinha o banco ao esquema. Num banco em que ela já está validada, não faz nada.
class ValidateTiersSegmentConstraint < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :tiers, name: "tiers_segment_unless_catch_all"
  end

  # Validar não se desfaz: a restrição continua existindo, como antes.
  def down; end
end
