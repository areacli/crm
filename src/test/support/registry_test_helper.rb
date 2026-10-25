# Cadastro do cliente para os testes (06): contato gravado direto, como se já existisse, com a forma normalizada calculada pelo código.
module RegistryTestHelper
  # Telefone ou e-mail (ou o contato dado em `attributes`) de um cliente. Origem tela e válido, salvo se `attributes` disser outra coisa.
  def add_contact(customer, kind, value, **attributes)
    parsed = Registry::Normalizer.public_send(kind, value)
    raise "contato de teste inválido: #{parsed}" if parsed.is_a?(String)

    customer.contacts.create!({ tenant_id: customer.tenant_id, kind: kind, key: parsed.key, value: parsed.value, origin: "screen", status: "valid" }.merge(attributes))
  end

  # Endereço de um cliente a partir dos campos, também com a forma normalizada.
  def add_address(customer, fields, **attributes)
    parsed = Registry::Normalizer.address(fields)
    raise "endereço de teste inválido: #{parsed}" unless parsed.is_a?(Registry::ParsedContact)

    customer.contacts.create!({ tenant_id: customer.tenant_id, kind: "address", key: parsed.key, value: parsed.value, origin: "screen", status: "valid" }.merge(parsed.address_attributes).merge(attributes))
  end
end
