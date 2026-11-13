require "test_helper"

# Lote de distribuição (14, R316): filtro da lista, segmento e planilha; conferência antes de valer, com a recusa da exclusividade por contrato;
# confirmação cria as distribuições de origem "lote".
class DistributionBatchesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @recupera = make_operation(@alfa)
    @fale = make_operation(@alfa, short_name: "Fale", cnpj: "11222333000181")
    @accreditation = Accreditation.find_by!(tenant: @alfa, operation: @recupera)
    @ana = make_customer(@alfa, document: FakeData.cpf(501), name: "Ana Lote", contract_code: "L-1")
    @bia = make_customer(@alfa, document: FakeData.cpf(502), name: "Bia Lote", contract_code: "L-2")
    sign_in_as users(:joana)
  end

  def batch_params(**extra) = { distribution_batch: { accreditation_id: @accreditation.id, exposure: "overdue", starts_on: Date.current.iso8601 }.merge(extra) }

  test "planilha de documentos: confere, lista o que não achou e confirma" do
    file = Rack::Test::UploadedFile.new(StringIO.new("documento\n#{Document.format(@ana.document)}\n#{FakeData.cpf(599)}\n"), "text/csv", original_filename: "lote.csv")
    # Na SPA, o envio abre o lote na aba dele, onde a conferência chega pelo tempo real.
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "file", file: file), headers: TRECHO }
    batch = DistributionBatch.last
    assert_equal distribution_batch_path(batch), evento_da_spa["navegar"]
    assert_predicate batch, :checked?
    assert_equal 1, batch.summary["targets"]
    assert_equal 1, batch.summary["missing_count"]
    get distribution_batch_url(batch), headers: TRECHO
    assert_includes response.body, "Vão 1 contratos"
    assert_select "button", text: "Confirmar o lote"
    perform_enqueued_jobs { post confirm_distribution_batch_url(batch), headers: TRECHO }
    assert evento_da_spa["atualizar"]
    assert_predicate batch.reload, :confirmed?
    get distribution_batch_url(batch), headers: TRECHO.merge("X-CRM-Fragmento" => "1") # o trecho vivo do resultado
    assert_select "#lote h2", text: "Lote confirmado"
    assert_equal [ [ @ana.id, "batch" ] ], Distribution.where(batch_id: batch.id).pluck(:customer_id, :source)
  end

  test "segmento de contratos, com a exclusividade recusando o contrato que está com outra operação" do
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: @fale, contract: Contract.find_by!(code: "L-2"))
    segment = make_segment(@alfa, "Todos os contratos", [ { "path" => "balance", "op" => "gt", "value" => 0 } ])
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "segment", segment_id: segment.id) }
    batch = DistributionBatch.last
    assert_equal "contract", batch.target
    assert_equal 1, batch.summary["refused_contracts"]
    assert_equal [ { "contract" => "L-2", "operation" => "Fale" } ], batch.summary["refused"]
    perform_enqueued_jobs { post confirm_distribution_batch_url(batch) }
    assert_equal [ Contract.find_by!(code: "L-1").id ], Distribution.where(batch_id: batch.id).pluck(:contract_id)
  end

  test "os clientes do filtro da lista" do
    get customers_url(busca: "Ana Lote"), headers: TRECHO
    assert_select "a[data-com-filtros]", text: "Distribuir estes clientes"
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "selection", selection: { busca: "Ana Lote" }) }
    assert_equal [ @ana.id ], DistributionBatch.last.entries
  end

  test "descartar deixa o lote como descartado, sem distribuições" do
    segment = make_segment(@alfa, "Todos os contratos", [ { "path" => "balance", "op" => "gt", "value" => 0 } ])
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "segment", segment_id: segment.id), headers: TRECHO }
    batch = DistributionBatch.last
    delete discard_distribution_batch_url(batch), headers: TRECHO
    assert_equal "Lote descartado.", evento_da_spa["aviso"]
    assert_predicate batch.reload, :discarded?
    get distribution_batch_url(batch), headers: TRECHO
    assert_select "p.vazio", text: /Lote descartado/
    assert_empty Distribution.where(batch_id: batch.id)
  end

  test "sem operação escolhida, a recusa diz isso" do
    post distribution_batches_url, params: batch_params(kind: "segment", accreditation_id: ""), headers: TRECHO
    assert_response :unprocessable_content
    assert_includes response.body, "Escolha a operação."
  end

  test "planilha com a coluna errada é recusada antes da conferência" do
    file = Rack::Test::UploadedFile.new(StringIO.new("cpf\n123\n"), "text/csv", original_filename: "lote.csv")
    post distribution_batches_url, params: batch_params(kind: "file", file: file), headers: TRECHO
    assert_response :unprocessable_content
    assert_includes response.body, "precisa da coluna documento ou da coluna contrato"
    assert_select "[data-refazer-no-erro] form" # a SPA troca a tela pela refeita, com a mensagem
  end


  test "17, R421: a coluna sistema acha o contrato do sistema; sem ela, o código de mais de um contrato é recusado e listado" do
    sap = SourceSystem.create!(tenant: @alfa, name: "SAP", key_kind: "natural")
    twin = Contract.create!(tenant: @alfa, source_system: sap, code: "L-1")
    ContractCustomer.create!(contract: twin, customer: @bia)
    l2 = Contract.find_by!(code: "L-2")
    file = ->(text) { Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: "lote.csv") }

    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "file", file: file.call("contrato\nL-1\nL-2\nL-9\n")) }
    batch = DistributionBatch.last
    assert_predicate batch, :checked?
    assert_equal [ l2.id ], batch.entries
    assert_equal [ [ "L-1" ], 1, [ "L-9" ] ], batch.summary.values_at("ambiguous", "ambiguous_count", "missing")
    get distribution_batch_url(batch), headers: TRECHO
    assert_includes response.body, "1 linhas da planilha ficam de fora porque o código é de mais de um contrato: L-1."

    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "file", file: file.call("contrato;sistema\nL-1;sap\nL-2;\nL-1;Totvs\n")) }
    batch = DistributionBatch.last
    assert_predicate batch, :checked?
    assert_equal [ twin.id, l2.id ].sort, batch.entries.sort
    assert_equal [ 0, [ "L-1 · Totvs" ] ], batch.summary.values_at("ambiguous_count", "missing")
  end
end
