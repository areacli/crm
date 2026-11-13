module Registry
  # Endereço com cidade inexistente (06, R126a): a cidade não existe na UF informada, pela lista de municípios do IBGE, com a mesma comparação da praça
  # (11, R249: nome sem acento e sem diferença de maiúsculas, e a UF). O endereço entra inválido, com este motivo, na tela e na carga, e não volta a
  # válido enquanto a cidade não existir. Com a lista vazia, nada é marcado. CEP, rua e número não são conferidos (sem serviço externo, M12).
  module AddressCheck
    REASON = "cidade inexistente".freeze
    # A mesma conferência em SQL, para ler a tabela de preparação da carga: `%{row}` é o apelido da linha com `kind`, `city` e `state`.
    UNKNOWN_CITY_SQL = <<~SQL.squish.freeze
      (%{row}.kind = 'address' and exists (select 1 from municipalities)
       and not exists (select 1 from municipalities m where m.state = upper(%{row}.state)
                       and m.name_key = translate(lower(btrim(%{row}.city)), '#{Portfolio::Query::ACCENTED}', '#{Portfolio::Query::PLAIN}')))
    SQL

    module_function

    # As cidades da lista, como [UF, nome sem acento]: quem confere um lote lê a lista uma vez, sem consulta por linha.
    def known_cities = Municipality.pluck(:state, :name_key).to_set

    # `known`: o conjunto de `known_cities`, quando o chamador confere muitos endereços.
    def unknown_city?(city, state, known = nil)
      return false if city.blank? || state.blank?

      key = [ state.to_s.strip.upcase, FoldedText.fold(city) ]
      return known.any? && !known.include?(key) if known

      Municipality.exists? && !Municipality.exists?(state: key.first, name_key: key.last)
    end

    # O contato (da ficha ou da linha da carga) é um endereço com cidade inexistente?
    def unknown_city_of?(contact, known = nil) = contact.kind.to_s == "address" && unknown_city?(contact.city, contact.state, known)
  end
end
