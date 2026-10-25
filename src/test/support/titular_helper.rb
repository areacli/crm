# Direitos do titular para os testes (07): cliente com tudo o que a anonimização precisa trocar, varredura do banco atrás de dado pessoal e
# fim da relação em datas conhecidas.
module TitularHelper
  PHONE = "(11) 98765-4321".freeze
  EMAIL = "maria.secreta@exemplo.com.br".freeze

  # Maria com contrato (um contrato próprio por documento, salvo `code`), título pago, pagamento (com documento), estorno com motivo, acionamento com texto, contatos, histórico e nota de divergência.
  # `ended_on` é a data do pagamento do título (o fim da relação).
  def make_full_customer(tenant = tenants(:alfa), ended_on: Date.current - 400, document: PaymentsHelper::MARIA, name: "Maria Souza", code: nil)
    code ||= "CT-#{document.delete("^0-9")[-4, 4]}"
    bill = make_bill(tenant, document: document, name: name, contract_code: code, number: "NF-MARIA-#{document[-2, 2]}", status: :paid)
    bill.update!(paid_cents: bill.amount_cents, paid_on: ended_on, description: "Mensalidade de Maria Souza")
    customer = bill.customer
    channel = tenant.payment_channels.first || make_channel(tenant)
    payment = Payment.create!(tenant: tenant, channel: channel, identifier: "PIX-#{customer.id}", document: document.delete("^0-9"), bill_number: bill.number, bill: bill,
                              paid_on: ended_on, amount_cents: bill.amount_cents, payment_method: "pix", status: "applied", applied_cents: bill.amount_cents, reversed_cents: 0)
    add_contact(customer, "phone", PHONE)
    add_contact(customer, "email", EMAIL)
    attempt = record_attempt(customer, users(:joana), text: "Maria disse que paga dia 10. Telefone da irmã 11 97777-0000.", contact_used: PHONE)
    Change.create!(tenant: tenant, user: users(:joana), subject_type: "customer", subject_id: customer.id, event: "updated", field: "name", before: "Maria S.", after: name, origin: "screen", note: "pedido da Maria")
    Change.create!(tenant: tenant, user: users(:joana), subject_type: "bill", subject_id: bill.id, event: "updated", field: "description", before: "Antiga de Maria Souza", after: "Mensalidade de Maria Souza")
    customer.define_singleton_method(:bill) { bill }
    customer.define_singleton_method(:payment) { payment }
    customer.define_singleton_method(:attempt) { attempt }
    customer
  end

  # Procura o texto em toda coluna de texto, varchar e jsonb do banco; devolve "tabela.coluna" onde achou.
  def find_in_database(*needles)
    columns = ActiveRecord::Base.connection.select_rows(<<~SQL)
      select table_name, column_name, data_type from information_schema.columns
      where table_schema = 'public' and data_type in ('character varying', 'text', 'jsonb') and table_name not in ('schema_migrations', 'ar_internal_metadata')
    SQL
    needles.flat_map do |needle|
      columns.filter_map do |table, column, type|
        expression = type == "jsonb" ? %("#{column}"::text) : %("#{column}")
        found = ActiveRecord::Base.connection.select_value("select 1 from #{table} where #{expression} ilike #{ActiveRecord::Base.connection.quote("%#{needle}%")} limit 1")
        "#{table}.#{column} (#{needle})" if found
      end
    end
  end

  def personal_needles = [ "Maria Souza", "52998224725", "529.982.247-25", "98765-4321", "987654321", EMAIL, "paga dia 10", "97777-0000", "Maria S.", "pedido da Maria" ]
end
