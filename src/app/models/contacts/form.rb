module Contacts
  # O que o formulário de registro precisa saber (R69 a R73): os valores enviados (para voltar preenchido quando algo é recusado), os resultados
  # ativos do credor, os contratos do cliente, os contatos da ficha dele (R71) e a sugestão do responsável financeiro (R69c, só aviso).
  class Form
    FIELDS = %i[channel result_id contract_id contact_used text contacted_at return_at save_contact].freeze

    attr_reader :customer, :values, :error

    def initialize(customer, values = {}, error: nil)
      @customer = customer
      @values = values.to_h.symbolize_keys.slice(*FIELDS)
      @error = error
    end

    def value(field) = values[field].to_s

    # Só resultados ativos são oferecidos, na ordem do credor (R67).
    def results = @results ||= customer.tenant.contact_results.active.ordered.to_a

    def selected_result = results.find { |result| result.id.to_s == values[:result_id].to_s }

    # R73: o campo de retorno só aparece quando o resultado escolhido o aceita ("não permite" esconde o campo).
    def return_rule = selected_result&.return_rule

    def show_return? = selected_result.present? && !selected_result.return_not_allowed?

    def contracts = @contracts ||= customer.contracts.where(tenant_id: customer.tenant_id).order(:code, :id).to_a

    def selected_contract = contracts.find { |contract| contract.id.to_s == values[:contract_id].to_s }

    # R71 e R120: os contatos oferecidos são os válidos do cliente contatado (nunca os de outro cliente do contrato), do tipo do canal escolhido:
    # telefone para telefone, WhatsApp e SMS; e-mail para e-mail; endereço para carta e presencial. Sem canal, todos os válidos.
    def suggested_contacts
      kind = CustomerContact::CHANNEL_KINDS[values[:channel]]
      contacts = customer.contacts.status_valid
      contacts = contacts.where(kind: kind) if kind
      contacts.order(:kind, :id).pluck(:value)
    end

    def save_contact? = values[:save_contact].to_s == "1"

    # R69c / MT-16: o responsável financeiro do contrato; sem nenhum declarado, os titulares. Devolve os nomes quando o cliente da ficha não
    # é um deles (aviso, nunca bloqueio); nil quando não há contrato escolhido ou o cliente é o próprio responsável.
    def other_responsible_names
      contract = selected_contract or return
      rows = ContractCustomer.where(contract_id: contract.id).includes(:customer).to_a
      responsible = rows.select { |row| row.roles.include?("financial_responsible") }
      responsible = rows.select { |row| row.roles.include?("holder") } if responsible.empty?
      return if responsible.any? { |row| row.customer_id == customer.id }

      responsible.map { |row| row.customer.name }.sort.presence
    end
  end
end
