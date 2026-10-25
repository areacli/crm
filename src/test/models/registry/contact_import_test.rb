require "test_helper"

# Contatos na carga (06, R109 a R111, R117, R118, R126, R108a): leitura, conferência e confirmação.
class Registry::ContactImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  EXTRA = %w[telefone2 telefone3 email2 logradouro numero complemento bairro cidade uf cep].freeze
  HEADER = (CsvHelper::HEADER + EXTRA).freeze
  MARIA = "529.982.247-25".freeze

  setup do
    @alfa = tenants(:alfa)
    @service = Portfolio::ImportService.new
    @maria = make_customer(@alfa, document: MARIA, name: "Maria da Silva")
  end

  def line(overrides = {}) = csv_line({ "telefone" => "", "email" => "" }.merge(overrides)).merge(EXTRA.index_with { |column| overrides[column].to_s }.compact)

  def send_file(lines, tenant: @alfa)
    import = @service.start(tenant: tenant, user: users(:joana), file: write_csv(lines, header: HEADER), mode: :incremental, original_name: "carteira.csv")
    perform_enqueued_jobs(only: CheckImportJob)
    import.reload
  end

  def confirm(import)
    @service.confirm(import)
    perform_enqueued_jobs(only: ConfirmImportJob)
    import.reload
  end

  def values(customer = @maria, scope: customer.contacts.reload) = scope.order(:kind, :key).pluck(:value)

  test "R109 e R108 (critério de aceite): a carga atualiza a data do contato que já existe, cria os novos e a seguinte, sem telefone2, não remove nada" do
    old = add_contact(@maria, "phone", "(11) 98765-4321", origin: "load", seen_in_import_at: 3.days.ago)
    full = { "telefone" => "(11) 98765-4321", "telefone2" => "(11) 2222-1111", "logradouro" => "Rua das Flores", "numero" => "120", "complemento" => "ap 3", "bairro" => "Centro",
             "cidade" => "São Paulo", "uf" => "SP", "cep" => "01001-000" }

    confirm(send_file([ line(full) ]))

    contacts = @maria.contacts.reload
    assert_equal 3, contacts.size
    assert_in_delta Time.current, old.reload.seen_in_import_at, 1.minute
    assert_equal [ "load" ], contacts.map(&:origin).uniq
    assert_equal "Rua das Flores, 120, ap 3, Centro, São Paulo/SP, CEP 01001-000", contacts.find(&:address?).value

    confirm(send_file([ line(full.except("telefone2")) ]))
    assert_equal 3, @maria.contacts.reload.size, "a carga nunca apaga um contato"
    confirm(send_file([ line("titulo" => "NF-9") ]))
    assert_equal 3, @maria.contacts.reload.size, "vazio não muda nada"
  end

  test "R109: dois contatos iguais na mesma linha viram um só, e o mesmo contato em duas linhas do cliente também" do
    confirm(send_file([ line("telefone" => "(11) 98765-4321", "telefone2" => "+55 11 98765-4321"), line("titulo" => "NF-2", "telefone" => "11987654321") ]))

    assert_equal [ "(11) 98765-4321" ], values
  end

  test "R111 (critério de aceite): CEP inválido na linha 3 aceita o título e a conferência lista 'endereço ignorado (CEP inválido)'" do
    import = send_file([ line("titulo" => "NF-1"), line("titulo" => "NF-2", "logradouro" => "Rua A", "cidade" => "X", "uf" => "SP", "cep" => "0100-000") ])

    summary = import.summary_data
    assert_equal [ 2, 0 ], [ summary[:valid], summary[:rejected] ]
    warning = import.warnings.sole
    assert_equal [ 3, "endereço ignorado (CEP inválido)" ], [ warning.line, warning.reason ]
    confirm(import)
    assert_equal 0, @maria.contacts.address.count
    assert_equal 2, Bill.where(customer: @maria, number: %w[NF-1 NF-2]).count
  end

  test "R111: telefone curto, e-mail sem domínio e endereço incompleto são ignorados com aviso, e os demais dados da linha entram" do
    import = send_file([ line("telefone" => "123", "email" => "maria.exemplo", "telefone2" => "(11) 2222-1111", "logradouro" => "Rua A") ])

    assert_equal [ "email ignorado (formato inválido)", "endereço ignorado (incompleto (falta cidade, UF e CEP))", "telefone ignorado (menos de 8 dígitos)" ], import.warnings.order(:reason).pluck(:reason)
    confirm(import)
    assert_equal [ "(11) 2222-1111" ], values
  end

  test "R125: telefone sem DDD é guardado como veio, com o aviso na conferência" do
    import = send_file([ line("telefone" => "98765-4321") ])

    assert_equal [ "telefone sem DDD (guardado como veio)" ], import.warnings.pluck(:reason)
    confirm(import)
    assert_equal [ "98765-4321" ], values
    assert @maria.contacts.sole.no_area_code?
  end

  test "R126 (critério de aceite): o mesmo telefone em outro formato só atualiza a data; o do credor entra inválido, com aviso na conferência" do
    @alfa.update!(phone: "(11) 3000-1000")
    existing = add_contact(@maria, "phone", "(11) 98765-4321", seen_in_import_at: nil)

    import = send_file([ line("telefone" => "+55 11 98765-4321", "telefone2" => "(11) 3000-1000") ])

    assert_equal [ "telefone igual ao do credor (entra inválido)" ], import.warnings.pluck(:reason)
    confirm(import)
    assert_equal 2, @maria.contacts.count
    assert_not_nil existing.reload.seen_in_import_at
    credor = @maria.contacts.find_by!(key: "1130001000")
    assert_equal [ "invalid", "é contato do credor", "load" ], [ credor.status, credor.reason, credor.origin ]
  end

  test "R117 e R118 (critério de aceite): com a tela prevalecendo, a conferência lista o que é mantido e, confirmada, o nome corrigido continua" do
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva Souza")
    dnd = add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20), kept_by_tenant: true)

    import = send_file([ line("nome" => "Maria da Silva", "telefone" => "(11) 3333-4444") ])

    kept = import.summary_data[:kept_by_tenant]
    assert_equal "screen", import.summary_data[:correction_policy]
    assert_equal [ 1, 1 ], [ kept[:names][:count], kept[:contacts][:count] ]
    assert_equal [ "Maria da Silva Souza", "Maria da Silva" ], kept[:names][:items].first.values_at(:current_name, :load_name)
    confirm(import)

    assert_equal [ "Maria da Silva Souza", true ], [ @maria.reload.name, @maria.name_kept ]
    assert_equal "do_not_disturb", dnd.reload.status
    assert_not_nil dnd.seen_in_import_at
    assert_equal 0, Change.where(subject_type: "customer", subject_id: @maria.id, import_id: import.id).count
  end

  test "R117 e R118 (critério de aceite): com a carga vencendo, o nome volta ao da carga e o contato não perturbe volta a válido, com registro" do
    @alfa.setting.update!(correction_policy: "load")
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva Souza")
    dnd = add_contact(@maria, "phone", "(11) 3333-4444", status: "do_not_disturb", do_not_disturb_on: Date.new(2026, 10, 20), kept_by_tenant: true)

    import = send_file([ line("nome" => "Maria da Silva", "telefone" => "(11) 3333-4444") ])
    assert_equal "load", import.summary_data[:correction_policy]
    assert_equal [ 1, 1 ], import.summary_data[:kept_by_tenant].then { |kept| [ kept[:names][:count], kept[:contacts][:count] ] }
    confirm(import)

    assert_equal [ "Maria da Silva", false ], [ @maria.reload.name, @maria.name_kept ]
    dnd.reload
    assert_equal [ "valid", "a carga vence", nil ], [ dnd.status, dnd.reason, dnd.do_not_disturb_on ]
    change = Change.find_by!(subject_type: "customer_contact", subject_id: dnd.id)
    assert_equal [ "do_not_disturb", "valid", "a carga vence", "load", import.id ], [ change.before, change.after, change.note, change.origin, change.import_id ]
    name_change = Change.find_by!(subject_type: "customer", subject_id: @maria.id, field: "name", import_id: import.id)
    assert_equal [ "Maria da Silva Souza", "Maria da Silva", "load" ], [ name_change.before, name_change.after, name_change.origin ]
  end

  test "R117: a carga vencendo não devolve a válido o contato igual ao do credor" do
    @alfa.setting.update!(correction_policy: "load")
    @alfa.update!(phone: "(11) 3000-1000")
    contact = add_contact(@maria, "phone", "(11) 3000-1000", status: "invalid", reason: "é contato do credor")

    confirm(send_file([ line("telefone" => "(11) 3000-1000") ]))

    assert_equal "invalid", contact.reload.status
  end

  test "R117: sem divergência não há 'mantido pelo credor' na conferência" do
    Registry::ContactEditor.new(users(:joana)).rename(@maria, "Maria da Silva")
    import = send_file([ line("nome" => "Maria da Silva") ])

    assert_equal [ 0, 0 ], import.summary_data[:kept_by_tenant].then { |kept| [ kept[:names][:count], kept[:contacts][:count] ] }
  end

  test "R117: a política trocada entre a conferência e a confirmação refaz a conferência e recusa a confirmação" do
    import = send_file([ line ])
    @alfa.setting.update!(correction_policy: "load")

    error = assert_raises(Portfolio::ImportRefused) { @service.confirm(import) }
    assert_match(/política de correção na tela ou carga mudou/, error.message)
  end

  test "R119: nomes divergentes no mesmo arquivo continuam recusando as linhas, com qualquer política, e os contatos delas não entram" do
    @alfa.setting.update!(correction_policy: "load")
    import = send_file([ line("nome" => "Maria A", "telefone2" => "(11) 2222-1111"), line("nome" => "Maria B", "titulo" => "NF-2", "telefone2" => "(11) 4444-5555") ])

    assert_equal 2, import.summary_data[:rejected]
    confirm(import)
    assert_equal [], values
  end

  test "R108a, MT-10 (critério de aceite): o mesmo CPF em dois credores tem contatos separados, e a carga de um credor não cria nem altera contato do outro" do
    beta = tenants(:beta)
    maria_beta = make_customer(beta, document: MARIA, name: "Maria Beta")
    add_contact(@maria, "phone", "(11) 98765-4321")

    confirm(send_file([ line("telefone" => "(11) 97777-0000") ], tenant: beta))

    assert_equal [ "(11) 97777-0000" ], values(maria_beta)
    assert_equal [ "(11) 98765-4321" ], values(@maria)
  end

  test "R126 (critério de aceite): o telefone da Alfa não invalida o mesmo número na carga da Beta, mas na da Alfa entra inválido" do
    @alfa.update!(phone: "(11) 3000-1000")
    beta = tenants(:beta)
    maria_beta = make_customer(beta, document: MARIA, name: "Maria Beta")

    confirm(send_file([ line("telefone" => "(11) 3000-1000") ], tenant: beta))
    confirm(send_file([ line("telefone" => "(11) 3000-1000") ]))

    assert_equal "valid", maria_beta.contacts.sole.status
    assert_equal "invalid", @maria.contacts.sole.status
  end

  test "R116: a carga registra a criação de contato só para cliente que já existia" do
    novo = "390.533.447-05"

    import = confirm(send_file([ line("telefone" => "(11) 97777-0000"), line("documento" => novo, "nome" => "João Pereira", "titulo" => "NF-8", "telefone" => "(11) 96666-0000") ]))

    created = Change.where(subject_type: "customer_contact", import_id: import.id, event: "created")
    assert_equal [ @maria.contacts.sole.id ], created.pluck(:subject_id)
    assert_equal 1, Customer.find_by!(document: Document.normalize(novo)).contacts.count
  end

  test "a conferência não grava contato nenhum (nada é gravado antes da confirmação)" do
    send_file([ line("telefone" => "(11) 97777-0000") ])

    assert_equal 0, @maria.contacts.count
  end
end
