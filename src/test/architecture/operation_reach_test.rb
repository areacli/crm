require "test_helper"

# Decisão 0024: o "está pra mim?" mora no banco. Toda tabela que guarda ou liga dado de carteira (cliente, contrato, fatura, acordo, promessa) tem
# RLS ligado e a política da operação; e a requisição sempre escolhe o papel do banco, sem controlador que pule.
class OperationReachArchitectureTest < ActiveSupport::TestCase
  LINKS = %w[customer_id contract_id bill_id agreement_id promise_id].freeze
  # As tabelas de alcance são consultadas pelas próprias políticas e só têm ids.
  EXEMPT = %w[operation_contracts operation_customers operation_bills].freeze

  test "toda tabela com cliente, contrato, fatura, acordo ou promessa tem RLS e política da operação" do
    connection = ActiveRecord::Base.connection
    tables = connection.tables.select { |table| (connection.columns(table).map(&:name) & LINKS).any? } - EXEMPT + %w[customers contracts bills]
    with_rls = connection.select_values("SELECT relname FROM pg_class WHERE relrowsecurity AND relkind = 'r'")
    with_policy = connection.select_values("SELECT DISTINCT tablename FROM pg_policies WHERE policyname = 'operation_read'")
    missing = tables.uniq.sort.reject { |table| with_rls.include?(table) && with_policy.include?(table) }
    assert_empty missing, "tabelas de carteira sem RLS da operação (decisão 0024): #{missing.join(', ')}"
  end

  # Os controladores fora do ApplicationController (página pública de pagamento, webhooks) não têm usuário: declaram o papel do sistema pelo
  # `SystemDbRole`. As páginas de erro não tocam no banco.
  NO_DATABASE = %w[ErrorsController].freeze

  test "todo controlador fora do ApplicationController declara o papel do sistema" do
    Rails.application.eager_load!
    controllers = (ActionController::Base.descendants + ActionController::API.descendants).select do |controller|
      controller.name && Object.const_source_location(controller.name)&.first.to_s.start_with?(Rails.root.join("app/controllers").to_s)
    end
    missing = controllers.reject { |controller| controller <= ApplicationController || controller.include?(SystemDbRole) || NO_DATABASE.include?(controller.name) }
    assert_empty missing.map(&:name).sort
  end

  test "nenhum controlador pula o papel do banco da requisição" do
    offenders = Rails.root.glob("app/controllers/**/*.rb").select { |file| File.read(file).match?(/skip_around_action|around_action.*(prepend|skip)/) }
    assert_empty offenders.map { |file| file.relative_path_from(Rails.root).to_s }
    assert_includes File.read(Rails.root.join("app/controllers/application_controller.rb")), "Operations::Context.for_user(Current.user)"
  end
end
