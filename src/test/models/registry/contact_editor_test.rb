require "test_helper"

# Edição do cadastro do cliente pela tela (R113 a R116), pelo acionamento (R121, R122) e a regra do contato do credor (R126).
class Registry::ContactEditorTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    @joana = users(:joana)
    @editor = Registry::ContactEditor.new(@joana)
  end

  def history(contact) = Change.where(subject_type: "customer_contact", subject_id: contact.id).order(:id)

  test "R113 e R116: acrescentar um contato tem origem tela, marca mantido pelo credor e entra no histórico com o autor" do
    contact = @editor.add(@maria, kind: "phone", fields: { value: "(11) 3333-4444" })

    assert_equal [ "phone", "1133334444", "screen", "valid", true ], [ contact.kind, contact.key, contact.origin, contact.status, contact.kept_by_tenant ]
    assert_equal @joana, contact.updated_by
    created = history(contact).sole
    assert_equal [ "created", @joana.id, "screen", "valid" ], [ created.event, created.user_id, created.origin, created.after ]
  end

  test "R113: acrescentar um endereço e um e-mail" do
    address = @editor.add(@maria, kind: "address", fields: { street: "Rua das Flores", number: "120", city: "São Paulo", state: "SP", zip: "01001-000" })
    email = @editor.add(@maria, kind: "email", fields: { value: "Maria@Exemplo.com.br" })

    assert_equal "Rua das Flores, 120, São Paulo/SP, CEP 01001-000", address.value
    assert_equal "maria@exemplo.com.br", email.key
  end

  test "caso de exceção: acrescentar um contato igual a um que já existe é recusado, dizendo a situação do existente" do
    @editor.add(@maria, kind: "phone", fields: { value: "(11) 98765-4321" })
    existing = @maria.contacts.sole
    existing.update!(status: "invalid", reason: "x")

    error = assert_raises(Registry::Refused) { @editor.add(@maria, kind: "phone", fields: { value: "+55 11 98765-4321" }) }
    assert_equal "Este contato já está cadastrado (inválido).", error.message
    assert_equal 1, @maria.contacts.count
  end

  test "R111 na tela: formato inválido é recusado com o motivo" do
    assert_equal "Telefone inválido: menos de 8 dígitos.", assert_raises(Registry::Refused) { @editor.add(@maria, kind: "phone", fields: { value: "12345" }) }.message
    assert_equal "E-mail inválido: formato inválido.", assert_raises(Registry::Refused) { @editor.add(@maria, kind: "email", fields: { value: "maria" }) }.message
    assert_equal "Endereço inválido: CEP inválido.", assert_raises(Registry::Refused) { @editor.add(@maria, kind: "address", fields: { street: "Rua A", city: "X", state: "SP", zip: "1" }) }.message
  end

  test "R113 (critério de aceite): corrigir deixa o antigo inválido com 'corrigido para' e cria o novo válido, as duas mudanças no histórico com o nome de Joana" do
    old = add_contact(@maria, "phone", "(11) 98765-4321", origin: "load")

    new = @editor.correct(old, value: "(11) 98765-4312")

    old.reload
    assert_equal [ "invalid", "corrigido para (11) 98765-4312" ], [ old.status, old.reason ]
    assert_equal [ "valid", "screen", true ], [ new.status, new.origin, new.kept_by_tenant ]
    assert_equal "load", old.origin, "a origem do antigo não muda"
    assert_equal @joana.id, history(old).sole.user_id
    assert_equal @joana.id, history(new).sole.user_id
  end

  test "caso de exceção: corrigir para um valor que já existe é recusado; igual ao atual também; contato inválido não se corrige" do
    old = add_contact(@maria, "phone", "(11) 98765-4321")
    add_contact(@maria, "phone", "(11) 98765-4312", status: "invalid", reason: "errado")

    assert_equal "Este contato já está cadastrado (inválido).", assert_raises(Registry::Refused) { @editor.correct(old, value: "(11) 98765-4312") }.message
    assert_equal "O novo valor é igual ao contato atual.", assert_raises(Registry::Refused) { @editor.correct(old, value: "11 98765 4321") }.message
    assert_equal "valid", old.reload.status
    invalid = @maria.contacts.find_by!(status: "invalid")
    assert_raises(Registry::Refused) { @editor.correct(invalid, value: "(11) 97777-7777") }
  end

  test "R113: marcar inválido exige motivo; voltar a válido exige motivo; ambos ficam no histórico" do
    contact = add_contact(@maria, "phone", "(11) 98765-4321")

    assert_equal "Informe o motivo.", assert_raises(Registry::Refused) { @editor.mark_invalid(contact, "  ") }.message
    @editor.mark_invalid(contact, "número de outra pessoa")
    assert_equal [ "invalid", "número de outra pessoa" ], [ contact.reload.status, contact.reason ]
    assert_raises(Registry::Refused) { @editor.restore(contact, "") }
    @editor.restore(contact, "o cliente confirmou o número")

    assert_equal "valid", contact.reload.status
    assert_equal %w[valid→invalid invalid→valid], history(contact).map { |change| "#{change.before}→#{change.after}" }
    assert_equal "número de outra pessoa", history(contact).first.note
  end

  test "R113 e R114: não perturbe vale por contato, com a data do pedido, sem prazo, até alguém voltar a válido" do
    contact = add_contact(@maria, "phone", "(11) 3333-4444")
    other = add_contact(@maria, "phone", "(11) 98765-4321")

    @editor.do_not_disturb(contact, Date.new(2026, 10, 20).iso8601, "pediu para não ligar no trabalho")

    contact.reload
    assert_equal [ "do_not_disturb", Date.new(2026, 10, 20) ], [ contact.status, contact.do_not_disturb_on ]
    assert_equal "valid", other.reload.status, "o outro contato do cliente continua válido"
    assert_match(/pedido em 20\/10\/2026/, history(contact).sole.note)
    assert_raises(Registry::Refused) { @editor.do_not_disturb(contact, Date.current.iso8601) }
    assert_raises(Registry::Refused) { @editor.do_not_disturb(other, (Date.current + 1).iso8601) }
    assert_raises(Registry::Refused) { @editor.do_not_disturb(other, "ontem") }
    @editor.restore(contact, "o cliente voltou a aceitar")
    assert_equal [ "valid", nil ], [ contact.reload.status, contact.do_not_disturb_on ]
  end

  test "R113: corrigir o nome marca o nome como mantido pelo credor e registra; o documento não se edita (R115)" do
    @editor.rename(@maria, "Maria da Silva Souza")

    @maria.reload
    assert_equal [ "Maria da Silva Souza", true ], [ @maria.name, @maria.name_kept ]
    change = Change.find_by!(subject_type: "customer", subject_id: @maria.id, field: "name")
    assert_equal [ "Maria Souza", "Maria da Silva Souza", @joana.id ], [ change.before, change.after, change.user_id ]
    assert_raises(Registry::Refused) { @editor.rename(@maria, " ") }
    assert_not Registry::ContactEditor.instance_methods.include?(:change_document), "não há como mudar o documento"
  end

  test "R126: contato igual ao do credor entra inválido na tela, com o motivo" do
    @alfa.update!(phone: "(11) 3000-1000")
    contact = @editor.add(@maria, kind: "phone", fields: { value: "11 3000 1000" })

    assert_equal [ "invalid", "é contato do credor" ], [ contact.status, contact.reason ]
    assert_equal "Este contato é do credor e não pode ficar válido.", assert_raises(Registry::Refused) { @editor.restore(contact, "tentativa") }.message
  end

  test "R126: o contato salvo do acionamento que é igual ao do credor também entra inválido" do
    @alfa.update!(email: "contato@exemplo.com.br")

    contact = @editor.save_from_attempt(@maria, "email", "Contato@Exemplo.com.br")

    assert_equal [ "invalid", "é contato do credor" ], [ contact.status, contact.reason ]
  end

  test "R122: o contato salvo do acionamento nasce válido, origem acionamento, sem a marca; o que já existe não duplica" do
    first = @editor.save_from_attempt(@maria, "phone", "(11) 4444-5555")
    again = @editor.save_from_attempt(@maria, "whatsapp", "11 4444-5555")

    assert_equal [ "valid", "contact_attempt", false ], [ first.status, first.origin, first.kept_by_tenant ]
    assert_equal first, again
    assert_nil @editor.save_from_attempt(@maria, "phone", "abc"), "texto que não é contato não é salvo"
    assert_nil @editor.save_from_attempt(@maria, "letter", "Rua A, 1")
  end

  test "R121: invalidar o contato usado marca o cadastrado, com motivo e data do acionamento, e ignora o que não está cadastrado" do
    contact = add_contact(@maria, "phone", "(11) 98765-4321")

    @editor.invalidate_used(@maria, "whatsapp", "11987654321", on: Date.new(2026, 10, 20))
    @editor.invalidate_used(@maria, "phone", "(11) 3333-4444", on: Date.new(2026, 10, 20))

    assert_equal [ "invalid", "inexistente, acionamento de 20/10" ], [ contact.reload.status, contact.reason ]
    assert_equal 1, @maria.contacts.count
    assert_equal "invalidated_by_result", history(contact).sole.event
  end
end
