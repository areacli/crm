require "test_helper"

# Registro de acionamentos (04): R69 a R77, um caso por regra.
class Contacts::RecorderTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @joana = users(:joana)
  end

  test "R69: registra no cliente contatado, com o credor dele, o tipo copiado do resultado e o histórico de alterações (R77)" do
    attempt = record_attempt(@customer, @joana, channel: "whatsapp", contact_used: "(11) 98765-4321", text: "Recebe dia 20")

    assert_equal [ @alfa.id, @customer.id, @joana.id, "whatsapp", "no_contact" ], attempt.values_at(:tenant_id, :customer_id, :user_id, :channel, :result_kind)
    assert_in_delta Time.current, attempt.contacted_at, 5.seconds
    change = Change.where(subject_type: "contact_attempt", subject_id: attempt.id).sole
    assert_equal [ "created", "Não atendeu", @joana.id, @alfa.id ], [ change.event, change.after, change.user_id, change.tenant_id ]
  end

  test "R65: canal fora da lista é recusado" do
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, channel: "pombo") }
    assert_equal "Escolha o canal do contato.", error.message
  end

  test "R66: o resultado é o da lista do credor do cliente; resultado de outro credor ou desativado é recusado" do
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: result_of(tenants(:beta), :no_answer)) }
    assert_equal "Escolha o resultado do contato.", error.message

    result = result_of(@alfa, :voicemail)
    result.update!(active: false)
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: result) }
    assert_equal "Resultado desativado; escolha outro.", error.message
    assert_equal 0, ContactAttempt.count
  end

  test "R70: a data do contato vale até 7 dias atrás; 3 dias atrás é aceito e 10 dias atrás ou o futuro são recusados" do
    three = record_attempt(@customer, @joana, contacted_at: 3.days.ago.strftime("%Y-%m-%dT%H:%M"))
    assert_in_delta 3.days.ago, three.contacted_at, 2.minutes
    assert_in_delta Time.current, three.created_at, 5.seconds

    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, contacted_at: 10.days.ago.strftime("%Y-%m-%dT%H:%M")) }
    assert_equal "Data do contato até 7 dias atrás.", error.message
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, contacted_at: 2.hours.from_now.strftime("%Y-%m-%dT%H:%M")) }
    assert_equal "A data do contato não pode ser futura.", error.message
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, contacted_at: "ontem") }
  end

  test "R71: o contato digitado fica só no acionamento, e o cadastro do cliente não muda" do
    @customer.update!(phone: "(11) 98765-4321")
    attempt = record_attempt(@customer, @joana, contact_used: "(11) 3333-4444")

    assert_equal "(11) 3333-4444", attempt.contact_used
    assert_equal "(11) 98765-4321", @customer.reload.phone
  end

  test "R71: o tamanho do contato usado depende do canal (telefone 60, e-mail 254, carta 300)" do
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, channel: "phone", contact_used: "9" * 61) }
    assert record_attempt(@customer, @joana, channel: "phone", contact_used: "9" * 60)
    assert record_attempt(@customer, @joana, channel: "email", contact_used: "a" * 242 + "@exemplo.com")
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, channel: "email", contact_used: "a" * 255) }
    assert record_attempt(@customer, @joana, channel: "letter", contact_used: "Rua " + "x" * 290)
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, channel: "in_person", contact_used: "x" * 301) }
  end

  test "R72: o texto é guardado como foi digitado (nada de formatação), sem caracteres de controle invisíveis e com as quebras de linha" do
    attempt = record_attempt(@customer, @joana, text: "<script>alert(1)</script>\r\nsegunda​ linha\u0007")

    assert_equal "<script>alert(1)</script>\nsegunda linha", attempt.text
  end

  test "R72: o texto tem no máximo 2.000 caracteres" do
    assert record_attempt(@customer, @joana, text: "a" * 2000)
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, text: "a" * 2001) }
    assert_equal "O texto tem no máximo 2000 caracteres.", error.message
  end

  test "R73: o resultado que exige retorno recusa sem data e aceita com ela" do
    required = result_of(@alfa, :call_back)
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: required) }
    assert_equal "Este resultado exige data de retorno.", error.message

    attempt = record_attempt(@customer, @joana, result: required, return_at: 2.days.from_now.strftime("%Y-%m-%dT%H:%M"))
    assert_in_delta 2.days.from_now, attempt.return_at, 2.minutes
  end

  test "R73: o resultado que não permite retorno recusa um envio forçado com retorno" do
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: result_of(@alfa, :wrong_number), return_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M")) }
    assert_equal "Este resultado não permite data de retorno.", error.message
    assert record_attempt(@customer, @joana, result: result_of(@alfa, :wrong_number))
  end

  test "R73: o retorno que é permitido é opcional, vem depois do contato e até 90 dias" do
    allowed = result_of(@alfa, :negotiating)
    assert_nil record_attempt(@customer, @joana, result: allowed).return_at
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: allowed, return_at: 1.hour.ago.strftime("%Y-%m-%dT%H:%M")) }
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, result: allowed, return_at: 120.days.from_now.strftime("%Y-%m-%dT%H:%M")) }
    assert_equal "Retorno até 90 dias depois do contato.", error.message
    assert record_attempt(@customer, @joana, result: allowed, return_at: 89.days.from_now.strftime("%Y-%m-%dT%H:%M"))
  end

  test "R69a: o acionamento fica no cliente contatado e não é copiado para os outros clientes do contrato" do
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-1")
    assert_equal ContractCustomer.where(contract: Contract.find_by(code: "CT-1")).count, 2

    record_attempt(pedro, @joana)

    assert_equal 1, pedro.contact_attempts.count
    assert_equal 0, @customer.contact_attempts.count
  end

  test "R69b: o contrato é opcional, do mesmo credor, e o cliente tem de figurar nele" do
    own = Contract.find_by!(tenant: @alfa, code: "CT-1")
    assert_equal own.id, record_attempt(@customer, @joana, contract_id: own.id).contract_id
    assert_nil record_attempt(@customer, @joana).contract_id

    other_customer = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Souza", contract_code: "CT-2")
    other_contract = other_customer.contracts.first
    error = assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, contract_id: other_contract.id) }
    assert_equal "O cliente não figura neste contrato.", error.message

    beta_contract = make_customer(tenants(:beta), contract_code: "CT-1").contracts.first
    assert_raises(Contacts::Refused) { record_attempt(@customer, @joana, contract_id: beta_contract.id) }
  end

  test "duplo envio: o mesmo registro do mesmo usuário em até 10 segundos é ignorado" do
    first = record_attempt(@customer, @joana, text: "Recebe dia 20")
    assert_equal first, record_attempt(@customer, @joana, text: "Recebe dia 20")
    assert_equal 1, ContactAttempt.count

    # Outro texto, outro usuário ou depois dos 10 segundos é outro acionamento.
    record_attempt(@customer, @joana, text: "Outro texto")
    record_attempt(@customer, users(:carlos), text: "Recebe dia 20")
    travel 11.seconds do
      record_attempt(@customer, @joana, text: "Recebe dia 20")
    end
    assert_equal 4, ContactAttempt.count
  end

  test "revisão 5: o acionamento é imutável; o erro se corrige com um acionamento novo, e o antigo continua como estava" do
    attempt = record_attempt(@customer, @joana, text: "cliente errado")

    assert attempt.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { attempt.update!(text: "outro") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { attempt.destroy }
    assert_not ContactAttempt.column_names.include?("voided_at")

    record_attempt(@customer, @joana, text: "Correção do registro anterior: o contato era de outro cliente.")
    assert_equal 2, @customer.contact_attempts.count
    assert_equal "cliente errado", attempt.reload.text
  end

  test "cada registro avisa o credor e o cliente pelo WebSocket, sem polling" do
    assert_broadcasts(ContactAttemptsChannel.broadcasting_for(@alfa), 1) do
      assert_broadcasts(ContactAttemptsChannel.broadcasting_for(@customer), 1) { @attempt = record_attempt(@customer, @joana) }
    end
  end
end
