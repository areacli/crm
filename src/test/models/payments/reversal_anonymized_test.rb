require "test_helper"

# Estorno de título de cliente anonimizado (03, revisão 5; 07, revisão 5). Vem de test/controllers/titular_screens_test.rb.
class Payments::ReversalAnonymizedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_full_customer(@alfa, code: "CT-7")
  end

  test "estorno é recusado quando todos os clientes do contrato estão anonimizados, e segue havendo um identificável" do
    Titular::Anonymizer.on_request(@maria, actor: users(:joana), reason: "pedido", document: @maria.document)
    import = run_payments_import([ reversal_line("identificador_pagamento" => @maria.payment.identifier, "valor" => "10,00") ], kind: "reversals")
    assert_equal [ "título de cliente anonimizado" ], import.rejections.pluck(:reason)

    Import.update_all(status: "discarded")
    pedro = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro", code: "CT-8")
    ContractCustomer.find_or_create_by!(contract: pedro.contracts.first, customer: @maria)
    import = run_payments_import([ reversal_line("identificador_pagamento" => pedro.payment.identifier, "identificador_estorno" => "E2", "valor" => "10,00") ], kind: "reversals")
    assert_empty import.rejections
  end
end
