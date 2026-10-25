module Contacts
  # O que o formulário de registro precisa saber (R69 a R73): os valores enviados (para voltar preenchido quando algo é recusado), os resultados
  # ativos do credor, os contratos do cliente, os contatos da ficha dele (R71) e a sugestão do responsável financeiro (R69c, só aviso).
  class Form
    FIELDS = %i[channel result_id contract_id contact_used text contacted_at return_at save_contact promise_contract_id promise_payment_method promise_on].freeze
    # O que o controlador aceita: os campos e a lista de títulos da promessa (10, R183).
    PERMITTED = [ *FIELDS, { promise_bill_ids: [] } ].freeze

    attr_reader :customer, :values, :error

    def initialize(customer, values = {}, error: nil)
      @customer = customer
      @values = values.to_h.symbolize_keys.slice(*FIELDS, :promise_bill_ids)
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

    # --- Promessa (10, R183): o bloco aparece quando o resultado escolhido admite promessa (R184).
    def promise_offered? = selected_result&.allows_promise? && !customer.anonymized?

    # O contrato do acionamento vale para a promessa (R69b); sem ele, o cliente escolhe um dos contratos dele (R183b).
    def promise_contract = selected_contract || contracts.find { |contract| contract.id.to_s == values[:promise_contract_id].to_s }

    def promise_contract_locked? = selected_contract.present?

    def promise_availability = @promise_availability ||= promise_contract && Promises::Availability.new(promise_contract)

    def promise_bill_ids = Array(values[:promise_bill_ids]).map(&:to_s)

    def promise_date = (Date.iso8601(values[:promise_on].to_s) rescue nil)

    # Dia do contato: o informado ou hoje (R70); só serve para dizer até quando vai o prazo.
    def contacted_on = (Time.zone.parse(values[:contacted_at].to_s)&.to_date rescue nil) || Date.current

    def promise_segment = promise_contract && Promises::Limits.segment_of(promise_contract)

    def promise_last_day = promise_segment && contacted_on + Promises::Limits.ceiling(promise_segment).days

    # Dias que o usuário dá sozinho no segmento, para dizer se a promessa nasce aberta ou aguarda aprovação (R191).
    def promise_own_days = promise_segment && Promises::Limits.days_for(Current.user, customer.tenant_id, promise_segment)

    # O valor de cada título na data prometida, mostrado antes de gravar (R186); nil enquanto faltam títulos ou data.
    def promise_quote
      return unless promise_contract && promise_date && promise_bill_ids.any?

      chosen = promise_availability.entries.select { |entry| entry.blocked.nil? && promise_bill_ids.include?(entry.bill.id.to_s) }.map(&:bill)
      Promises::Pricing.quote(customer.tenant, chosen, promise_date) if chosen.any?
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
