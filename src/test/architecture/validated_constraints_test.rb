require "test_helper"

# Restrição criada com `validate: false` numa migração precisa de uma migração posterior que a valide. Sem isso, o banco criado migração a migração
# (o da demonstração) fica com a restrição "não validada" e diverge do `schema.rb`, que a registra como validada: foi o que aconteceu com
# `tiers_segment_unless_catch_all` entre 30/10 e 13/11/2026.
class ValidatedConstraintsArchitectureTest < ActiveSupport::TestCase
  test "toda restrição criada sem validar é validada por uma migração posterior" do
    migrations = Rails.root.glob("db/migrate/*.rb").sort.map { |file| [ file.basename.to_s, file.read ] }
    pending = migrations.flat_map do |name, source|
      source.scan(/^\s*add_(?:check_constraint|foreign_key)\b[^\n]*name: "([^"]+)"[^\n]*validate: false/).flatten.reject do |constraint|
        migrations.any? { |later, text| later > name && text.match?(/validate_(?:check_constraint|foreign_key)\b[^\n]*name: "#{Regexp.escape(constraint)}"/) }
      end.map { |constraint| "#{constraint} (#{name})" }
    end
    assert_empty pending, "restrições criadas com validate: false e nunca validadas: #{pending.join(', ')}"
  end

  test "nenhuma restrição do banco de teste está não validada" do
    names = ActiveRecord::Base.connection.select_values("SELECT conname FROM pg_constraint WHERE NOT convalidated")
    assert_empty names
  end
end
