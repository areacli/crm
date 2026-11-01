require "test_helper"

# R314 (decisão 0024): o usuário de operação percorre todas as rotas de leitura do sistema, com todas as permissões de carteira, e nenhuma
# resposta traz o nome, o documento ou um número de fatura da cliente que não está pra a operação. O teste não conhece as telas: se uma tela
# nova esquecer o recorte, ela aparece aqui, porque o recorte não é dela.
class OperationReachRoutesTest < ActionDispatch::IntegrationTest
  HIDDEN_NAME = "Bia Escondida".freeze

  setup do
    @alfa = tenants(:alfa)
    operation = make_operation(@alfa)
    profile = operator_profile(@alfa, permissions: %w[view_portfolio record_contact_attempts edit_customer_registry negotiate_agreements administer_agreements cancel_payment_promises])
    profile.update!(permissions: %w[view_portfolio record_contact_attempts edit_customer_registry negotiate_agreements administer_agreements cancel_payment_promises])
    @caio = make_operation_user(operation, @alfa, profile: profile)
    @ana = make_customer(@alfa, document: FakeData.cpf(201), name: "Ana Visível", contract_code: "C-VIS")
    @hidden = make_customer(@alfa, document: FakeData.cpf(202), name: HIDDEN_NAME, contract_code: "C-OCULTO")
    @hidden_bill = @hidden.bills.first
    add_contact(@hidden, "phone", "(11) 97777-0202")
    Distribution.create!(tenant: @alfa, operation: operation, contract: Contract.find_by!(code: "C-VIS"), exposure: "all", starts_on: Date.current - 1)
    Operations::ReachBuilder.new(@alfa).rebuild
  end

  # Cada parâmetro de rota recebe o registro escondido do tipo que o nome indica (cliente, contrato, fatura); o resto, o id do cliente escondido.
  def fill(route)
    ids = { "customer" => @hidden.id, "contract" => @hidden_bill.contract_id, "bill" => @hidden_bill.id }
    controller = route.defaults[:controller].to_s
    route.path.spec.to_s.sub("(.:format)", "").gsub(/:(\w+)/) do
      name = Regexp.last_match(1)
      key = name == "id" ? controller.split("/").last.singularize : name.delete_suffix("_id")
      ids.fetch(key, @hidden.id).to_s
    end
  end

  # As páginas de erro como em produção: a página detalhada do ambiente de teste mostra o código do próprio teste, onde estão os segredos.
  def with_production_errors
    config = Rails.application.env_config
    previous = config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    config.merge!("action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false)
    yield
  ensure
    config.merge!(previous)
  end

  test "nenhuma rota de leitura mostra a cliente que não está pra a operação" do
    sign_in_as @caio
    with_production_errors { walk_routes }
  end

  def walk_routes
    routes = Rails.application.routes.routes.select { |route| route.verb == "GET" && route.defaults[:controller].present? }
                  .reject { |route| route.defaults[:controller].start_with?("rails/", "active_storage/", "action_mailbox/") || route.path.spec.to_s.include?("*") }
    checked = 0
    routes.each do |route|
      path = fill(route)
      get path
      checked += 1
      body = response.body
      [ HIDDEN_NAME, @hidden.document, Document.format(@hidden.document), @hidden_bill.number, "97777-0202" ].each do |secret|
        assert_not_includes body, secret, "#{route.defaults[:controller]}##{route.defaults[:action]} (#{path}) mostrou #{secret}"
      end
    end
    assert_operator checked, :>, 50
  end

  # Os formulários que abrem sem credor escolhido (credenciar, distribuir, lote) quebravam com a política por credor: o gestor percorre todas as
  # rotas de leitura sem parâmetro, e nenhuma responde com erro.
  test "o gestor do credor abre toda rota de leitura sem parâmetro sem erro" do
    sign_in_as users(:joana)
    failures = []
    checked = 0
    with_production_errors do
      Rails.application.routes.routes.select { |route| route.verb == "GET" && route.defaults[:controller].present? && !route.path.spec.to_s.sub("(.:format)", "").include?(":") }
           .reject { |route| route.defaults[:controller].start_with?("rails/", "active_storage/", "action_mailbox/") || route.path.spec.to_s.include?("*") }
           .each do |route|
        path = route.path.spec.to_s.sub("(.:format)", "")
        get path
        failures << "#{path}: #{response.status}" if response.status >= 500
        checked += 1
      end
    end
    assert_empty failures
    assert_operator checked, :>, 40
  end

  test "a lista, a busca e a ficha da operação mostram só o que está pra ela" do
    sign_in_as @caio
    get customers_url
    assert_includes response.body, "Ana Visível"
    get customers_url(q: "Bia")
    assert_not_includes response.body, HIDDEN_NAME
    get customer_url(@hidden)
    assert_response :not_found
    get customer_url(@ana)
    assert_response :success
  end
end
