require "test_helper"

# Enquadramento da distribuição (14, R342 a R347): incluir um segmento passa pela conferência do impacto; confirmar cria as distribuições de
# origem "regra"; o contrato que sai do segmento tem a da regra encerrada; a distribuição à mão vence a regra.
class DistributionRulesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @recupera = make_operation(@alfa)
    @old = make_contract(@alfa, "R-OLD", bills: [ { overdue: 120, cents: 100_000 } ])
    @young = make_contract(@alfa, "R-NEW", bills: [ { overdue: 10, cents: 50_000 } ])
    @segment = make_segment(@alfa, "Atraso longo", [ { "path" => "overdue_days", "op" => "gt", "value" => 90 } ])
    sign_in_as users(:joana)
  end

  def include_segment
    perform_enqueued_jobs do
      post settings_distribution_rules_url(tenant_id: @alfa.id), params: { rule: { segment_id: @segment.id, exposure: "overdue", position: 0, operation_ids: [ @recupera.id ] } }
    end
    follow_redirect!
  end

  test "incluir, conferir e confirmar: o contrato do segmento vai para a operação pela regra" do
    include_segment
    assert_response :success
    assert_select "tbody tr", text: /Recupera.*1/m
    token = request.params[:token]
    perform_enqueued_jobs { post confirm_settings_distribution_rules_url(tenant_id: @alfa.id, token: token) }
    distribution = Distribution.find_by!(contract: @old)
    assert_equal [ "rule", @recupera.id ], [ distribution.source, distribution.operation_id ]
    assert_nil Distribution.find_by(contract: @young)

    @old.bills.update_all(due_date: Date.current - 5)
    DistributionRules::Recalculation.new(@alfa).apply
    assert_equal "left_segment", distribution.reload.end_reason
  end

  test "a conferência velha é recusada" do
    include_segment
    token = request.params[:token]
    @alfa.setting.update!(distribution_rules_version: 99)
    post confirm_settings_distribution_rules_url(tenant_id: @alfa.id, token: token)
    assert_match "mudou depois", flash[:alert]
  end

  test "R344: contrato distribuído à mão não é tocado pela regra" do
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: make_operation(@alfa, short_name: "Fale", cnpj: "11222333000181"), contract: @old)
    @alfa.setting.update!(operation_exclusive: false)
    include_segment
    perform_enqueued_jobs { post confirm_settings_distribution_rules_url(tenant_id: @alfa.id, token: request.params[:token]) }
    assert_nil Distribution.find_by(contract: @old, source: "rule")
  end

  test "com a exclusividade, um item não tem duas operações" do
    fale = make_operation(@alfa, short_name: "Fale", cnpj: "11222333000181")
    post settings_distribution_rules_url(tenant_id: @alfa.id), params: { rule: { segment_id: @segment.id, exposure: "overdue", position: 0, operation_ids: [ @recupera.id, fale.id ] } }
    assert_response :unprocessable_content
    assert_includes response.body, "uma operação só"
  end
end
