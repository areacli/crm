module Portfolio
  # Grava na carteira um lote de clientes da importação: o cliente, os contatos, os contratos, as ligações com papéis, os títulos, as divergências de
  # valor, as versões de valor e os acréscimos informados (R7 a R9b, R13 a R16, R57, R88 a R102, R108 a R126). Chamado dentro de uma transação, uma por
  # lote. Active Record sobre os modelos (validações e callbacks valem) e auditoria por `Change.record_many!` (decisão 0021). Consultas do lote:
  # `customers (tenant_id, document)`, `contracts (tenant_id, code)`, `bills (tenant_id, customer_id, number)`, `customer_contacts (customer_id, kind, key)`.
  class ConfirmBatch
    Entry = Struct.new(:row, :customer, :contract, :bill, :amount_cents, :outcome, :before_amount)

    def initialize(import)
      @import = import
      @tenant = import.tenant
      @setting = @tenant.setting
      @policy = @setting.discrepancy_policy
      @screen_prevails = @setting.correction_policy_screen?
      @sender = import.user
      @decider = import.confirmed_by || import.user
    end

    def call(documents)
      rows = ImportRow.where(import_id: @import.id, ok: true, document: documents).order(:line).to_a
      contacts = ImportContact.where(import_id: @import.id, document: documents).order(:line).to_a
      @changes = []
      @now = Time.current
      customers = write_customers(rows, documents)
      write_contacts(contacts, customers)
      write_bills(rows, customers)
      Change.record_many!(@changes, tenant_id: @import.tenant_id, actor: @sender, import: @import)
    end

    private
      # R8 e R117: a mudança de nome fica registrada; com "a tela prevalece", o nome marcado "mantido pelo credor" não muda. Sem "a tela prevalece",
      # a carga vence e a marca cai. O nome vem da última linha válida do documento.
      def write_customers(rows, documents)
        names = rows.group_by(&:document).transform_values { |lines| lines.max_by(&:line).name }
        customers = Customer.where(tenant_id: @import.tenant_id, document: documents).index_by(&:document)
        @new_documents = Set.new
        documents.each do |document|
          name = names.fetch(document)
          customer = customers[document]
          if customer.nil?
            customers[document] = Customer.create!(tenant: @tenant, document: document, name: name)
            @new_documents << document
          elsif customer.name != name && !(customer.name_kept && @screen_prevails)
            @changes << [ customer, "updated", { field: "name", before: customer.name, after: name, origin: "load" } ]
            customer.update!(name: name, name_kept: false)
          elsif customer.name_kept && !@screen_prevails
            customer.update!(name_kept: false)
          end
        end
        customers
      end

      # Contatos da carga (06, R109, R117, R126): um contato igual a um que o cliente já tem só atualiza a data em que veio (com "a carga vence", também
      # o devolve a válido, com registro); o novo é criado, inválido se for igual ao do credor. A carga nunca apaga nem desativa um contato.
      def write_contacts(contacts, customers)
        return if contacts.empty?

        existing = CustomerContact.where(customer_id: customers.values.map(&:id)).index_by { |contact| [ contact.customer_id, contact.kind, contact.key ] }
        load_wins = !@screen_prevails
        contacts.each do |row|
          customer = customers.fetch(row.document)
          contact = existing[[ customer.id, row.kind, row.key ]]
          if contact
            touch_contact(contact, load_wins && !contact.status_valid? && !row.tenant_contact)
          else
            existing[[ customer.id, row.kind, row.key ]] = create_contact(customer, row)
          end
        end
      end

      def touch_contact(contact, reactivate)
        before = contact.status
        contact.seen_in_import_at = @now
        if reactivate
          contact.assign_attributes(status: "valid", reason: "a carga vence", do_not_disturb_on: nil, kept_by_tenant: false, updated_by: nil, updated_at: @now)
          @changes << [ contact, "status_changed", { field: "status", before: before, after: "valid", note: "a carga vence", origin: "load" } ]
        end
        contact.save!(touch: false)
      end

      def create_contact(customer, row)
        contact = CustomerContact.create!(tenant: @tenant, customer: customer, kind: row.kind, key: row.key, value: row.value, street: row.street, number: row.number,
                                          complement: row.complement, district: row.district, city: row.city, state: row.state, zip: row.zip, origin: "load",
                                          status: row.tenant_contact ? "invalid" : "valid", reason: (row.tenant_contact ? "é contato do credor" : nil),
                                          kept_by_tenant: false, seen_in_import_at: @now)
        unless @new_documents.include?(customer.document)
          @changes << [ contact, "created", { field: "status", after: contact.status, note: contact.reason, origin: "load" } ]
        end
        contact
      end

      def write_bills(rows, customers)
        customer_ids = customers.values.map(&:id)
        contracts = declared_contracts(rows)
        omission = omission_contracts(rows, customers)
        links = ContractCustomer.where(customer_id: customer_ids).index_by { |link| [ link.contract_id, link.customer_id ] }
        bills = Bill.where(tenant_id: @import.tenant_id, customer_id: customer_ids).index_by { |bill| [ bill.customer_id, bill.number ] }

        entries = rows.map do |row|
          customer = customers.fetch(row.document)
          contract = row.contract ? contracts.fetch(row.contract) : omission.fetch(customer.id)
          # Cliente de cada contrato declarado, com os papéis padrão (vazios até o fim do lote).
          links[[ contract.id, customer.id ]] ||= ContractCustomer.create!(contract: contract, customer: customer, roles: [])
          Entry.new(row, customer, contract, bills[[ customer.id, row.number ]], row.amount_cents)
        end
        entries.each { |entry| evaluate_discrepancy(entry) }
        # R57: título pago neste sistema continua pago e não é atualizado pela carga.
        entries.reject! { |entry| entry.bill && %w[paid renegotiated].include?(entry.bill.status) }
        write_roles(entries, links)
        entries.each { |entry| write_bill(entry) }
        settle(entries)
        write_versions(entries)
        write_surcharges(entries)
      end

      def declared_contracts(rows)
        codes = rows.filter_map(&:contract).uniq
        contracts = Contract.where(tenant_id: @import.tenant_id, code: codes).index_by(&:code)
        (codes - contracts.keys).each { |code| contracts[code] = Contract.create!(tenant: @tenant, code: code, created_by_omission: false) }
        contracts
      end

      # Contrato por omissão (MT-14): um por cliente, reaproveitado nas cargas seguintes.
      def omission_contracts(rows, customers)
        ids = rows.reject(&:contract).map { |row| customers.fetch(row.document).id }.uniq
        return {} if ids.empty?

        found = Contract.where(tenant_id: @import.tenant_id, created_by_omission: true).joins(:contract_customers).where(contract_customers: { customer_id: ids })
                        .select("contracts.*, contract_customers.customer_id AS owner_id").order(:id).to_a.group_by(&:owner_id).transform_values(&:first)
        customers.each_value do |customer|
          next unless ids.include?(customer.id) && !found.key?(customer.id)

          contract = Contract.create!(tenant: @tenant, code: nil, created_by_omission: true)
          ContractCustomer.create!(contract: contract, customer: customer, roles: [])
          found[customer.id] = contract
        end
        found
      end

      # R93 a R98: o título com pagamento cujo valor muda ganha uma divergência aberta, com o efeito da política da hora da confirmação. Com "manter e
      # registrar", o valor informado fica só na divergência e o título segue com o vigente. Roda antes do R57 porque o título pago também gera
      # divergência, só para registro (R96).
      def evaluate_discrepancy(entry)
        bill = entry.bill
        return unless bill && bill.amount_cents != entry.row.amount_cents && DiscrepancyRules.with_allocation?(bill)

        entry.outcome = DiscrepancyRules.evaluate(bill, entry.row.amount_cents, @policy)
        entry.amount_cents = bill.amount_cents if entry.outcome.effect == "kept"
        @discrepancy_bill_ids ||= ValueDiscrepancy.where(import_id: @import.id).pluck(:bill_id).to_set
        return if @discrepancy_bill_ids.include?(bill.id)

        outcome = entry.outcome
        ValueDiscrepancy.create!(tenant: @tenant, bill: bill, import: @import, previous_cents: bill.amount_cents, reported_cents: entry.row.amount_cents,
                                 allocated_cents: bill.paid_cents, balance_before_cents: outcome.balance_before_cents, balance_after_cents: outcome.balance_after_cents,
                                 excess_cents: outcome.excess_cents, effect: outcome.effect, policy: @policy.to_s, status: "open")
        @discrepancy_bill_ids << bill.id
      end

      # R9b: a união do que as linhas declaram (coluna vazia vale os dois papéis), somada ao que o cliente já tinha; uma carga nunca remove papel.
      def write_roles(entries, links)
        entries.group_by { |entry| [ entry.contract.id, entry.customer.id ] }.each do |key, group|
          declared = []
          declared << "holder" if group.any? { |entry| entry.row.roles.nil? || entry.row.roles.include?("holder") }
          declared << "financial_responsible" if group.any? { |entry| entry.row.roles.nil? || entry.row.roles.include?("financial_responsible") }
          link = links.fetch(key)
          merged = (link.roles | declared).sort
          link.update!(roles: merged) unless merged == link.roles
        end
      end

      # R13: valor, vencimento, contrato e descrição de título existente são atualizados, com registro. R16: título retirado que volta fica ativo, com o
      # registro "retirado em X, reincluído em Y".
      def write_bill(entry)
        row = entry.row
        bill = entry.bill
        if bill.nil?
          entry.bill = Bill.new(tenant: @tenant, contract: entry.contract, customer: entry.customer, number: row.number, due_date: row.due_date, amount_cents: entry.amount_cents,
                                description: row.description, product: row.product, status: "active", last_import_id: @import.id, version_user: @decider)
          entry.bill.save!
          return
        end

        entry.before_amount = bill.amount_cents
        { amount_cents: entry.amount_cents, due_date: row.due_date, description: row.description }.each do |field, value|
          @changes << [ bill, "updated", { field: field.to_s, before: bill[field]&.to_s, after: value&.to_s } ] if bill[field] != value
        end
        if bill.contract_id != entry.contract.id
          @changes << [ bill, "updated", { field: "contract", before: bill.contract.code, after: entry.contract.code } ]
        end
        @changes << [ bill, "reincluded", { field: "status", before: "withdrawn", after: "active" } ] if bill.withdrawn?
        bill.update!(contract: entry.contract, due_date: row.due_date, amount_cents: entry.amount_cents, description: row.description, product: row.product || bill.product,
                     status: "active", withdrawn_at: nil, withdrawn_import_id: nil, last_import_id: @import.id)
      end

      # Os títulos que a política "seguir" quitou passam a pago (R94, R97).
      def settle(entries)
        entries.each do |entry|
          next unless entry.bill && %w[becomes_paid returns_paid].include?(entry.outcome&.effect)

          bill = entry.bill
          @changes << [ bill, "settled_by_value", { field: "status", before: "active", after: "paid" } ]
          # A data de hoje é a de Brasília (a do banco seria a de UTC, um dia à frente depois das 21h).
          paid_on = Payment.where(bill_id: bill.id, status: "applied").maximum(:paid_on) || Date.current
          bill.update!(status: "paid", paid_on: paid_on)
        end
      end

      # R88: a versão do valor nasce para o título novo (no callback do modelo) e para o que mudou de valor.
      def write_versions(entries)
        entries.each do |entry|
          next unless entry.before_amount && entry.before_amount != entry.bill.amount_cents

          BillValueVersion.create!(tenant: @tenant, bill: entry.bill, amount_cents: entry.bill.amount_cents, import: @import, user: @decider)
        end
      end

      # R102: os acréscimos já aplicados pelo credor, guardados só para conferência; uma linha por título, a da última carga que os trouxe.
      def write_surcharges(entries)
        entries.each do |entry|
          row = entry.row
          next if [ row.penalty_cents, row.interest_cents, row.correction_cents, row.other_cents ].all?(&:nil?)

          surcharge = ReportedSurcharge.find_or_initialize_by(bill_id: entry.bill.id)
          surcharge.update!(tenant: @tenant, import: @import, penalty_cents: row.penalty_cents.to_i, interest_cents: row.interest_cents.to_i,
                            correction_cents: row.correction_cents.to_i, other_cents: row.other_cents.to_i)
        end
      end
  end
end
