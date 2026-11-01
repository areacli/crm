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
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "file", file: file) }
    batch = DistributionBatch.last
    assert_predicate batch, :checked?
    assert_equal 1, batch.summary["targets"]
    assert_equal 1, batch.summary["missing_count"]
    get distribution_batch_url(batch)
    assert_includes response.body, "Vão 1 contratos"
    perform_enqueued_jobs { post confirm_distribution_batch_url(batch) }
    assert_predicate batch.reload, :confirmed?
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
    get customers_url(q: "Ana Lote")
    assert_select "a", text: "Distribuir estes clientes"
    perform_enqueued_jobs { post distribution_batches_url, params: batch_params(kind: "selection", selection: { q: "Ana Lote" }) }
    assert_equal [ @ana.id ], DistributionBatch.last.entries
  end

  test "planilha com a coluna errada é recusada antes da conferência" do
    file = Rack::Test::UploadedFile.new(StringIO.new("cpf\n123\n"), "text/csv", original_filename: "lote.csv")
    post distribution_batches_url, params: batch_params(kind: "file", file: file)
    assert_response :unprocessable_content
    assert_includes response.body, "uma coluna só"
  end
end
