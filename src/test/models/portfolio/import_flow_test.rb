require "test_helper"

# Critérios de aceite e regras R1 a R16 da especificação 01: conferência (nada é gravado) e confirmação (grava só o válido, numa transação).
class Portfolio::ImportFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  MARIA = "529.982.247-25".freeze
  JOAO = "390.533.447-05".freeze
  ANA = "111.444.777-35".freeze

  setup do
    @tenant = tenants(:alfa)
    @user = users(:joana)
    @service = Portfolio::ImportService.new
  end

  def send_file(lines, mode: :incremental, tenant: @tenant)
    import = @service.start(tenant: tenant, user: @user, file: write_csv(lines), mode: mode, original_name: "carteira.csv")
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def confirm(import)
    @service.confirm(import)
    perform_enqueued_jobs(only: ConfirmImportJob)
    import.reload
  end

  def standard_lines
    [ csv_line("documento" => MARIA, "titulo" => "NF-1", "valor" => "100,00"), csv_line("documento" => MARIA, "titulo" => "NF-2", "valor" => "200,00"),
      csv_line("documento" => JOAO, "nome" => "João Pereira", "contrato" => "CT-2", "titulo" => "NF-3", "valor" => "300,00"),
      csv_line("documento" => JOAO, "nome" => "João Pereira", "contrato" => "CT-2", "titulo" => "NF-4", "valor" => "400,00"),
      csv_line("documento" => ANA, "nome" => "Ana Souza", "contrato" => "", "titulo" => "NF-5", "valor" => "500,00") ]
  end

  test "a conferência mostra 3 clientes, 5 títulos e a soma exata, e não grava nada" do
    import = send_file(standard_lines)

    assert import.checked?
    summary = import.summary_data
    assert_equal [ 5, 3, 150_000, 0 ], [ summary[:valid], summary[:customers], summary[:amount_cents], summary[:rejected] ]
    assert_equal "1.500,00", summary[:amount_formatted]
    assert_equal 1, summary[:contracts_created_by_omission]
    assert_equal 0, Customer.count
    assert_equal 0, Bill.count
  end

  test "a confirmação grava clientes, contratos e títulos; o contrato por omissão nasce sem código" do
    import = confirm(send_file(standard_lines))

    assert import.confirmed?
    assert_equal 3, Customer.where(tenant: @tenant).count
    assert_equal 5, Bill.where(tenant: @tenant).count
    assert_equal 150_000, Bill.where(tenant: @tenant).sum(:amount_cents)
    assert_equal %w[CT-1 CT-2], Contract.where(tenant: @tenant, created_by_omission: false).order(:code).pluck(:code)
    omission = Contract.where(tenant: @tenant, created_by_omission: true)
    assert_equal 1, omission.count
    assert_nil omission.first.code
    assert_equal Customer.find_by!(document: Document.normalize(ANA)), omission.first.customers.first
    assert_equal 0, Portfolio::Sql.rows("select 1 from import_rows where import_id = #{import.id}").size
    assert_not File.exist?(import.file_path)
  end

  test "linhas recusadas aparecem com o motivo, e as válidas seguem (R2 a R7)" do
    lines = [ csv_line("titulo" => "NF-1"), csv_line("documento" => "111.111.111-11", "titulo" => "NF-2"), csv_line("titulo" => "NF-1", "valor" => "9,00"),
              csv_line("documento" => JOAO, "titulo" => "NF-3", "valor" => "12,345"), csv_line("documento" => ANA, "titulo" => "NF-4", "vencimento" => "31/02/2026"),
              csv_line("documento" => JOAO, "nome" => "João Pereira", "titulo" => "NF-6"), csv_line("documento" => JOAO, "nome" => "João Pereira Silva", "titulo" => "NF-7") ]
    import = send_file(lines)
    reasons = import.rejections.order(:line).pluck(:line, :reason).to_h

    assert_equal "CPF inválido", reasons[3]
    assert_equal "título repetido na linha 2", reasons[4]
    assert_equal "valor com mais de duas casas decimais", reasons[5]
    assert_equal "data inválida", reasons[6]
    assert_equal "nomes diferentes para o mesmo documento: linhas 7 e 8", reasons[7]
    assert_equal "nomes diferentes para o mesmo documento: linhas 7 e 8", reasons[8]
    assert_equal 1, import.summary_data[:valid]
    assert_equal 6, import.summary_data[:rejected]
  end

  test "nome com maiúsculas, acento ou espaços diferentes é o mesmo nome (R7)" do
    import = send_file([ csv_line("nome" => "MARIA  da Silva", "titulo" => "NF-1"), csv_line("nome" => "Maria da Silva", "titulo" => "NF-2") ])

    assert_equal 2, import.summary_data[:valid]
    assert_equal 0, import.summary_data[:rejected]
  end

  test "o batimento retira o título ausente; reincluir é voltar a ativo, com o registro (R11, R14, R16)" do
    confirm(send_file(standard_lines))

    batimento = send_file(standard_lines.first(3), mode: :full_sync)
    assert_equal({ "count" => 2, "amount_cents" => 90_000 }, batimento.summary_data[:to_withdraw].stringify_keys)
    confirm(batimento)

    assert_equal %w[withdrawn withdrawn], Bill.where(number: %w[NF-4 NF-5]).pluck(:status)
    assert_equal "withdrawn", Bill.find_by!(number: "NF-4").status
    assert_equal "active", Bill.find_by!(number: "NF-1").status
    assert Change.exists?(subject_type: "bill", event: "withdrawn", subject_id: Bill.find_by!(number: "NF-4").id)

    volta = confirm(send_file([ standard_lines[3] ]))
    assert volta.confirmed?
    assert_equal "active", Bill.find_by!(number: "NF-4").status
    assert Change.exists?(subject_type: "bill", event: "reincluded", subject_id: Bill.find_by!(number: "NF-4").id)
  end

  test "o incremental não retira o que não vem no arquivo, e atualizar registra antes e depois (R11, R13)" do
    confirm(send_file(standard_lines))
    confirm(send_file([ csv_line("documento" => MARIA, "titulo" => "NF-1", "valor" => "150,00", "vencimento" => "20/09/2026") ]))

    assert_equal "active", Bill.find_by!(number: "NF-5").status
    bill = Bill.find_by!(number: "NF-1")
    assert_equal 15_000, bill.amount_cents
    assert_equal Date.new(2026, 9, 20), bill.due_date
    change = Change.find_by!(subject_type: "bill", subject_id: bill.id, field: "amount_cents")
    assert_equal [ "10000", "15000" ], [ change.before, change.after ]
    assert_equal @user, change.user
  end

  test "linha recusada no batimento mantém o título gravado (R15)" do
    confirm(send_file(standard_lines))
    batimento = send_file([ csv_line("documento" => MARIA, "titulo" => "NF-1", "vencimento" => "31/02/2026"), standard_lines[1] ], mode: :full_sync)

    assert_equal 1, batimento.summary_data[:kept_by_rejection]
    confirm(batimento)
    assert_equal "active", Bill.find_by!(number: "NF-1").status
  end

  test "nome mudado fica registrado e contato vazio não apaga o anterior (R8, R109)" do
    confirm(send_file([ csv_line("nome" => "Maria da Silva", "telefone" => "(11) 98765-4321") ]))
    confirm(send_file([ csv_line("nome" => "Maria da Silva Souza", "telefone" => "", "email" => "", "titulo" => "NF-2") ]))

    customer = Customer.find_by!(document: Document.normalize(MARIA))
    assert_equal "Maria da Silva Souza", customer.name
    assert_equal [ "(11) 98765-4321", "maria@exemplo.com.br" ], customer.contacts.status_valid.order(:kind).pluck(:value).sort_by { |value| value.include?("@") ? 1 : 0 }
    change = Change.find_by!(subject_type: "customer", subject_id: customer.id, field: "name")
    assert_equal [ "Maria da Silva", "Maria da Silva Souza" ], [ change.before, change.after ]
  end

  test "o mesmo documento em outro credor é outro cliente, e a carga não mexe no outro (MT-9)" do
    confirm(send_file([ csv_line("nome" => "Maria Alfa") ]))
    confirm(send_file([ csv_line("nome" => "Maria Beta") ], tenant: tenants(:beta)))

    assert_equal [ "Maria Alfa", "Maria Beta" ], Customer.order(:name).pluck(:name)
    assert_equal 2, Customer.where(document: Document.normalize(MARIA)).count
    assert_equal 2, Contract.where(code: "CT-1").count
  end

  test "papéis: o declarado acrescenta e nunca remove (R9b)" do
    confirm(send_file([ csv_line("papel" => "titular") ]))
    contract_customer = ContractCustomer.first
    assert_equal [ "holder" ], contract_customer.roles

    confirm(send_file([ csv_line("papel" => "responsável financeiro", "titulo" => "NF-2") ]))
    assert_equal %w[financial_responsible holder], contract_customer.reload.roles.sort
  end

  test "coluna papel vazia vale os dois papéis" do
    confirm(send_file([ csv_line("papel" => "") ]))

    assert_equal %w[financial_responsible holder], ContractCustomer.first.roles.sort
  end

  test "só uma importação por credor por vez; descartar libera o credor (R10)" do
    first = send_file(standard_lines)

    error = assert_raises(Portfolio::ImportRefused) { @service.start(tenant: @tenant, user: @user, file: write_csv(standard_lines), mode: :incremental) }
    assert_equal "há uma importação em andamento", error.message
    assert @service.start(tenant: tenants(:beta), user: @user, file: write_csv(standard_lines), mode: :incremental)

    @service.discard(first)
    assert first.reload.discarded?
    assert @service.start(tenant: @tenant, user: @user, file: write_csv(standard_lines), mode: :incremental)
  end

  test "arquivo inválido é recusado inteiro, com o motivo" do
    import = send_file([])
    assert import.rejected?
    assert_equal "arquivo sem linhas de dados", import.failure_reason
  end

  test "só se confirma ou se descarta importação conferida" do
    import = send_file(standard_lines)
    confirm(import)

    assert_raises(Portfolio::ImportRefused) { @service.confirm(import) }
    assert_raises(Portfolio::ImportRefused) { @service.discard(import) }
  end

  test "falha na confirmação desfaz tudo e marca a importação como falha" do
    import = send_file(standard_lines)
    Portfolio::Sql.connection.execute("alter table bills add constraint teste_falha check (number <> 'NF-5')")
    confirm(import)

    assert import.failed?
    assert_equal 0, Customer.count
    assert_equal 0, Bill.count
  ensure
    Portfolio::Sql.connection.execute("alter table bills drop constraint if exists teste_falha")
  end

  test "cada mudança de situação vai ao canal do credor, e o andamento só a cada cinco pontos" do
    stream = ImportsChannel.broadcasting_for(@tenant)
    import = nil

    assert_broadcasts(stream, 1) { import = @service.start(tenant: @tenant, user: @user, file: write_csv(standard_lines), mode: :incremental) }
    Rails.cache.clear
    assert_broadcasts(stream, 2) do
      import.update!(progress_percent: 10)
      import.update!(progress_percent: 12)
      import.update!(progress_percent: 15)
    end
    assert_broadcasts(stream, 1) { import.update!(status: :checking) }
  end
end
