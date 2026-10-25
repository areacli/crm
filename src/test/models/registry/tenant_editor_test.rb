require "test_helper"

# Cadastro do credor (R106, R106a, R126): CNPJ validado, razão social obrigatória, histórico, CNPJ único e o efeito do contato do credor.
class Registry::TenantEditorTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @joana = users(:joana)
    @editor = Registry::TenantEditor.new(@joana)
  end

  def attributes(overrides = {}) = { cnpj: "11.222.333/0001-81", legal_name: "Comércio Exemplo Ltda", trade_name: "Exemplo" }.merge(overrides)

  test "R106 (critério de aceite): CNPJ inválido é recusado; com CNPJ e razão social válidos salva e o painel mostra o nome fantasia" do
    error = assert_raises(ActiveRecord::RecordInvalid) { @editor.update(@alfa, attributes(cnpj: "11.111.111/1111-11")) }
    assert_includes error.record.errors.full_messages, "CNPJ inválido"
    assert_nil @alfa.reload.cnpj

    @editor.update(@alfa, attributes)

    @alfa.reload
    assert_equal [ "11222333000181", "Comércio Exemplo Ltda", "Exemplo", "Exemplo" ], [ @alfa.cnpj, @alfa.legal_name, @alfa.trade_name, @alfa.display_name ]
  end

  test "R106: a razão social é obrigatória; o nome fantasia é opcional e o painel cai para a razão social" do
    assert_raises(ActiveRecord::RecordInvalid) { @editor.update(@alfa, attributes(legal_name: " ")) }

    @editor.update(@alfa, attributes(trade_name: ""))
    assert_equal "Comércio Exemplo Ltda", @alfa.reload.display_name
  end

  test "R106: aceita CNPJ alfanumérico (como na R2) e o endereço segue a R110" do
    @editor.update(@alfa, attributes(cnpj: "12.ABC.345/01DE-35", street: "Rua das Flores", city: "São Paulo", state: "sp", zip: "01001-000"))

    @alfa.reload
    assert_equal [ "12ABC34501DE35", "SP", "01001000", "s/n" ], [ @alfa.cnpj, @alfa.state, @alfa.zip, @alfa.number ]
    error = assert_raises(ActiveRecord::RecordInvalid) { @editor.update(@alfa, attributes(street: "Rua A", city: "", state: "SP", zip: "01001-000")) }
    assert_includes error.record.errors.full_messages.join, "Endereço inválido: incompleto (falta cidade)"
  end

  test "R106: toda mudança fica no histórico com antes, depois, quem e quando; sem mudança não registra" do
    @editor.update(@alfa, attributes)
    @editor.update(@alfa, attributes(trade_name: "Exemplo Ltda"))
    @editor.update(@alfa, attributes(trade_name: "Exemplo Ltda"))

    changes = Change.where(subject_type: "tenant", subject_id: @alfa.id).order(:id)
    assert_equal %w[cnpj legal_name trade_name trade_name], changes.map(&:field)
    last = changes.last
    assert_equal [ "Exemplo", "Exemplo Ltda", @joana.id, "screen" ], [ last.before, last.after, last.user_id, last.origin ]
  end

  test "R106: dois credores com o mesmo CNPJ são recusados, na tela e no comando que cria o credor" do
    @editor.update(@alfa, attributes)

    error = assert_raises(ActiveRecord::RecordInvalid) { @editor.update(tenants(:beta), attributes) }
    assert_includes error.record.errors.full_messages, "já existe um credor com este CNPJ"
    assert_raises(ActiveRecord::RecordInvalid) { Tenant.provision!("Credor novo", cnpj: "11222333000181", legal_name: "Outra Ltda") }
    assert_nil Tenant.find_by(name: "Credor novo")
    assert_equal "45723174000110", Tenant.provision!("Credor com CNPJ", cnpj: "45.723.174/0001-10", legal_name: "Nova Ltda").cnpj
  end

  test "R106a: cada credor tem o seu cadastro, sem interferência" do
    @editor.update(@alfa, attributes)
    @editor.update(tenants(:beta), attributes(cnpj: "45.723.174/0001-10", legal_name: "Clínica Beta SA", trade_name: ""))

    assert_equal [ "Exemplo", "Clínica Beta SA" ], [ @alfa.reload.display_name, tenants(:beta).reload.display_name ]
  end

  test "R126: o telefone e o e-mail do credor ganham a forma normalizada, e e-mail ou telefone inválidos são recusados" do
    @editor.update(@alfa, attributes(phone: "(11) 3000-1000", email: "Contato@Exemplo.com.br"))

    assert_equal [ "1130001000", "contato@exemplo.com.br" ], [ @alfa.reload.phone_key, @alfa.email_key ]
    assert_raises(ActiveRecord::RecordInvalid) { @editor.update(@alfa, attributes(phone: "123")) }
    assert_raises(ActiveRecord::RecordInvalid) { @editor.update(@alfa, attributes(email: "sem-arroba")) }
  end

  test "R126: se o credor cadastra depois um contato que clientes já têm, esses contatos passam a inválidos, com o motivo e o registro; os de outro credor não" do
    maria = make_customer(@alfa)
    joao = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "João")
    beta = make_customer(tenants(:beta), document: PaymentsHelper::MARIA, name: "Maria Beta")
    equal = [ maria, joao, beta ].map { |customer| add_contact(customer, "phone", "(11) 3000-1000") }
    other = add_contact(maria, "phone", "(11) 98765-4321")

    @editor.update(@alfa, attributes(phone: "+55 (11) 3000-1000"))

    assert_equal %w[invalid invalid valid], equal.map { |contact| contact.reload.status }
    assert_equal "é contato do credor", equal.first.reason
    assert_equal "valid", other.reload.status
    change = Change.find_by!(subject_type: "customer_contact", subject_id: equal.first.id)
    assert_equal [ "valid", "invalid", @joana.id ], [ change.before, change.after, change.user_id ]
  end
end
