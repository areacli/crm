module Contacts
  # Lista inicial de resultados (R68): cada credor novo recebe uma cópia e depois a edita sozinho, sem afetar os outros.
  module InitialResults
    LIST = [
      [ "Pediu para retornar depois", :spoke_with_customer, :required ], [ "Negociação em andamento", :spoke_with_customer, :allowed ],
      [ "Disse que já pagou", :spoke_with_customer, :allowed ], [ "Contesta a dívida", :spoke_with_customer, :allowed ],
      [ "Recusou pagar", :spoke_with_customer, :allowed ], [ "Recado com terceiro", :spoke_with_third_party, :allowed ],
      [ "Terceiro não conhece o cliente", :spoke_with_third_party, :not_allowed ], [ "Não atendeu", :no_contact, :allowed ],
      [ "Caixa postal", :no_contact, :allowed ], [ "Mensagem enviada, sem resposta", :no_contact, :allowed ],
      [ "Número ou endereço inexistente", :no_contact, :not_allowed ]
    ].freeze

    def self.create_for(tenant)
      LIST.each_with_index do |(name, kind, rule), index|
        tenant.contact_results.create!(name: name, kind: kind, return_rule: rule, position: index + 1)
      end
    end
  end
end
