module Registry
  # Contato já validado e normalizado (R125). `value` é o texto exibido; `key` é a forma normalizada, usada para comparar. Os campos do
  # endereço só existem para o tipo `address`. `warning` guarda um aviso que não impede o contato (telefone sem DDD).
  ParsedContact = Data.define(:kind, :key, :value, :street, :number, :complement, :district, :city, :state, :zip, :warning) do
    def self.simple(kind, key, value, warning = nil) = new(kind, key, value, nil, nil, nil, nil, nil, nil, nil, warning)

    def address_attributes = to_h.slice(:street, :number, :complement, :district, :city, :state, :zip)
  end
end
