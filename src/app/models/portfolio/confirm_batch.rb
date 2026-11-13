module Portfolio
  # Grava na carteira um lote de clientes da importação: o cliente, os contatos, os contratos, as ligações com papéis, os títulos, as divergências de
  # valor, as versões de valor e os acréscimos informados (R7 a R9b, R13 a R16, R57, R88 a R102, R108 a R126). Chamado dentro de uma transação, uma por
  # lote. Active Record sobre os modelos (validações e callbacks valem) e auditoria por `Change.record_many!` (decisão 0021).
  #
  # A carga entra por um sistema do credor (17, R403 a R415): contratos e títulos são procurados e criados só dentro dele, pela chave dele (documento e
  # número e código do contrato, em chave natural; id do título e id do contrato, em id próprio); o cliente é um só por credor e documento, e a
  # política "Cadastro entre sistemas" diz se esta carga muda o nome dele. Consultas do lote: `customers (tenant_id, document)`, `customer_contacts
  # (customer_id, kind, key)`, `customer_identities (tenant_id, external_id, source_system_id)`, `changes (subject_type, subject_id)`, e os índices
  # parciais por sistema de `contracts` e de `bills` (com `external_id IS NULL` ou `IS NOT NULL`, conforme a chave).
  class ConfirmBatch
    Entry = Struct.new(:row, :customer, :contract, :bill, :amount_cents, :outcome, :before_amount)

    def initialize(import)
      @import = import
      @tenant = import.tenant
      # O sistema pai do que esta carga cria (17, R403).
      @system = import.source_system
      @own_id = @system.key_own_id?
      @setting = @tenant.setting
      @policy = @setting.discrepancy_policy
      @screen_prevails = @setting.correction_policy_screen?
      @sender = import.user
      @decider = import.confirmed_by || import.user
      @record_policy = CustomerRecordPolicy.new(@setting, @system)
      @identity_resolver = IdentityResolver.new(import)
    end

    def call(documents)
      rows = ImportRow.where(import_id: @import.id, ok: true, document: documents).order(:line).to_a
      contacts = ImportContact.where(import_id: @import.id, document: documents).order(:line).to_a
      @changes = []
      # Linhas que este lote não aplica (R409a): vão ao resultado como ignoradas.
      @unapplied = {}
      @now = Time.current
      customers = write_customers(rows, documents)
      rows = resolve_identities(rows, customers)
      write_contacts(contacts.reject { |contact| @unapplied.key?(contact.line) }, customers)
      write_bills(rows, customers)
      Change.record_many!(@changes, tenant_id: @import.tenant_id, actor: @sender, import: @import)
      return if @unapplied.empty?

      ImportRejection.insert_all!(@unapplied.map { |line, reason| { import_id: @import.id, line: line, reason: reason, ignored: true } })
    end

    private
      # R8 e R117: a mudança de nome fica registrada; com "a tela prevalece", o nome marcado "mantido pelo credor" não muda. Sem "a tela prevalece",
      # a carga vence e a marca cai. O nome vem da última linha válida do documento. Depois disso vale o "Cadastro entre sistemas" (17, R410 a R413):
      # o cliente guarda os sistemas que o informaram, e a carga de um sistema que não prevalece não muda o nome; o que ela trazia fica no histórico.
      def write_customers(rows, documents)
        names = rows.group_by(&:document).transform_values { |lines| lines.max_by(&:line).name }
        customers = Customer.where(tenant_id: @import.tenant_id, document: documents).index_by(&:document)
        @new_documents = Set.new
        @overruled = Set.new
        ignored = []
        documents.each do |document|
          name = names.fetch(document)
          customer = customers[document]
          if customer.nil?
            customers[document] = Customer.create!(tenant: @tenant, document: document, name: name, source_system_ids: [ @system.id ])
            @new_documents << document
            next
          end

          prevails = @record_policy.prevails?(customer)
          @overruled << customer.id unless prevails
          customer.source_system_ids |= [ @system.id ]
          if customer.name != name && !(customer.name_kept && @screen_prevails)
            if prevails
              @changes << [ customer, "updated", { field: "name", before: customer.name, after: name, origin: "load" } ]
              customer.assign_attributes(name: name, name_kept: false)
            else
              ignored << [ customer, name ]
            end
          elsif customer.name_kept && !@screen_prevails && prevails
            customer.name_kept = false
          end
          customer.save! if customer.changed?
        end
        record_ignored_names(ignored)
        customers
      end

      # R411: o nome que a carga trazia e não entrou fica no histórico do cliente, uma vez por sistema e por nome (a carga diária não repete o registro).
      def record_ignored_names(ignored)
        return if ignored.empty?

        seen = Change.where(subject_type: "customer", subject_id: ignored.map { |customer, _| customer.id }, event: "name_ignored", source_system_id: @system.id)
                     .pluck(:subject_id, :after).to_set
        ignored.each do |customer, name|
          next if seen.include?([ customer.id, name ])

          @changes << [ customer, "name_ignored", { field: "name", before: customer.name, after: name, origin: "load", note: "cadastro entre sistemas: #{@system.name} não prevalece" } ]
        end
      end

      # R408 e R409a: a identidade remota de cada linha com `id_cliente`. A linha cuja identidade é de outro documento, sem confirmação, não é aplicada.
      def resolve_identities(rows, customers)
        result = @identity_resolver.call(rows, customers)
        @identities = result.by_line
        @changes.concat(result.changes)
        @unapplied.merge!(result.unapplied)
        result.unapplied.empty? ? rows : rows.reject { |row| result.unapplied.key?(row.line) }
      end

      # Contatos da carga (06, R109, R117, R126): um contato igual a um que o cliente já tem só atualiza a data em que veio (com "a carga vence", também
      # o devolve a válido, com registro); o novo é criado, inválido se for igual ao do credor. A carga nunca apaga nem desativa um contato. Entre
      # sistemas (17, R412), os contatos se somam e cada um guarda os sistemas que o informaram; só a carga do sistema que prevalece reativa um contato.
      def write_contacts(contacts, customers)
        return if contacts.empty?

        existing = CustomerContact.where(customer_id: customers.values.map(&:id)).index_by { |contact| [ contact.customer_id, contact.kind, contact.key ] }
        load_wins = !@screen_prevails
        contacts.each do |row|
          customer = customers.fetch(row.document)
          contact = existing[[ customer.id, row.kind, row.key ]]
          # R126a: a carga conserta a cidade do endereço que o sistema marcou, salvo quando o cadastro deste sistema não prevalece (17, R411 e R412).
          if contact && unknown_city?(contact) && !unknown_city?(row) && (load_wins || !contact.kept_by_tenant) && !@overruled.include?(customer.id)
            fix_city(contact, row)
          elsif contact
            touch_contact(contact, load_wins && !contact.status_valid? && !row.tenant_contact && !unknown_city?(contact) && !@overruled.include?(customer.id))
          else
            existing[[ customer.id, row.kind, row.key ]] = create_contact(customer, row)
          end
        end
      end

      def touch_contact(contact, reactivate)
        before = contact.status
        contact.seen_in_import_at = @now
        contact.source_system_ids |= [ @system.id ]
        if reactivate
          contact.assign_attributes(status: "valid", reason: "a carga vence", do_not_disturb_on: nil, kept_by_tenant: false, updated_by: nil, updated_at: @now)
          @changes << [ contact, "status_changed", { field: "status", before: before, after: "valid", note: "a carga vence", origin: "load" } ]
        end
        contact.save!(touch: false)
      end

      # R126a: o endereço com cidade inexistente entra inválido e não volta a válido enquanto a cidade não existir. A lista de municípios é lida uma vez
      # por lote. `row`: a linha da carga ou o contato que o cliente já tem.
      def unknown_city?(row) = row.kind == "address" && Registry::AddressCheck.unknown_city_of?(row, @known_cities ||= Registry::AddressCheck.known_cities)

      # R126a: a carga traz o mesmo endereço (CEP, número e logradouro) com uma cidade que existe: ele ganha a cidade e volta a válido.
      def fix_city(contact, row)
        before = contact.status
        contact.source_system_ids |= [ @system.id ]
        contact.assign_attributes(city: row.city, state: row.state, district: row.district, complement: row.complement, value: row.value, status: "valid",
                                  reason: "cidade corrigida pela carga", do_not_disturb_on: nil, kept_by_tenant: false, updated_by: nil, updated_at: @now, seen_in_import_at: @now)
        @changes << [ contact, "status_changed", { field: "status", before: before, after: "valid", note: "cidade corrigida pela carga", origin: "load" } ]
        contact.save!(touch: false)
      end

      def create_contact(customer, row)
        reason = row.tenant_contact ? "é contato do credor" : (Registry::AddressCheck::REASON if unknown_city?(row))
        contact = CustomerContact.create!(tenant: @tenant, customer: customer, kind: row.kind, key: row.key, value: row.value, street: row.street, number: row.number,
                                          complement: row.complement, district: row.district, city: row.city, state: row.state, zip: row.zip, origin: "load",
                                          status: reason ? "invalid" : "valid", reason: reason,
                                          kept_by_tenant: false, seen_in_import_at: @now, source_system_ids: [ @system.id ])
        unless @new_documents.include?(customer.document)
          @changes << [ contact, "created", { field: "status", after: contact.status, note: contact.reason, origin: "load" } ]
        end
        contact
      end

      def write_bills(rows, customers)
        customer_ids = customers.values.map(&:id)
        bills = existing_bills(rows, customer_ids)
        rows = hold_debtor_changes(rows, customers, bills)
        contracts = @own_id ? contracts_by_id(rows) : declared_contracts(rows)
        omission = @own_id ? {} : omission_contracts(rows, customers)
        links = ContractCustomer.where(customer_id: customer_ids).index_by { |link| [ link.contract_id, link.customer_id ] }

        entries = rows.map do |row|
          customer = customers.fetch(row.document)
          contract = if @own_id then contracts.fetch(row.external_contract_id)
          else row.contract ? contracts.fetch(row.contract) : omission.fetch(customer.id)
          end
          # A ligação nova fica em memória até `write_roles`, que a grava já com os papéis.
          links[[ contract.id, customer.id ]] ||= ContractCustomer.new(contract: contract, customer: customer, roles: [])
          Entry.new(row, customer, contract, bills[@own_id ? row.external_bill_id : [ customer.id, row.number ]], row.amount_cents)
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

      # Os títulos que as linhas do lote podem atualizar, só os do sistema da carga (R403): em chave natural, os dos clientes do lote, por cliente e
      # número; em id próprio, os dos ids que vieram, de quem quer que sejam (a troca de devedor é mudança a confirmar, R405).
      def existing_bills(rows, customer_ids)
        scope = Bill.where(tenant_id: @import.tenant_id, source_system_id: @system.id)
        return scope.where(external_id: nil, customer_id: customer_ids).index_by { |bill| [ bill.customer_id, bill.number ] } unless @own_id

        scope.where.not(external_id: nil).where(external_id: rows.map(&:external_bill_id).uniq).index_by(&:external_id)
      end

      # R405 e R409a: em id próprio, a linha cujo título é de outro cliente só é aplicada com a mudança confirmada na conferência e sem promessa nem
      # acordo em aberto no título. A conferência já tirou das válidas as não confirmadas; o que sobra aqui é o que mudou entre a conferência e a
      # confirmação, e fica como estava, listado no resultado. O título pago ou renegociado não é atualizado pela carga (R57), nem muda de cliente.
      def hold_debtor_changes(rows, customers, bills)
        return rows unless @own_id

        moving = rows.select { |row| bills[row.external_bill_id]&.customer_id&.!=(customers.fetch(row.document).id) }
        return rows if moving.empty?

        blocked = Holds.blocked_reasons(moving.map { |row| bills.fetch(row.external_bill_id).id })
        dropped = moving.reject do |row|
          bill = bills.fetch(row.external_bill_id)
          next false if %w[paid renegotiated].include?(bill.status)

          reason = if blocked[bill.id] then "troca de devedor não aplicada: #{blocked[bill.id]}"
          elsif !(row.hold_confirmed && %w[debtor both].include?(row.hold_kind)) then Holds::UNCONFIRMED.fetch("debtor")
          end
          @unapplied[row.line] = reason if reason
          reason.nil?
        end
        rows - dropped
      end

      # Em chave natural o contrato é o código, dentro do sistema (R403).
      def declared_contracts(rows)
        codes = rows.filter_map(&:contract).uniq
        contracts = Contract.where(tenant_id: @import.tenant_id, source_system_id: @system.id, external_id: nil, code: codes).index_by(&:code)
        (codes - contracts.keys).each { |code| contracts[code] = Contract.create!(tenant: @tenant, source_system: @system, code: code, created_by_omission: false) }
        contracts
      end

      # Em id próprio o contrato é o id que o sistema manda; o código é dado, e mudar o código atualiza o contrato, com histórico (R405). Vale o código
      # da última linha do lote que o trouxe.
      def contracts_by_id(rows)
        codes = rows.each_with_object({}) { |row, found| found[row.external_contract_id] = row.contract if row.contract.present? }
        ids = rows.map(&:external_contract_id).uniq
        contracts = Contract.where(tenant_id: @import.tenant_id, source_system_id: @system.id).where.not(external_id: nil).where(external_id: ids).index_by(&:external_id)
        ids.each do |id|
          contract = contracts[id]
          code = codes[id]
          if contract.nil?
            contracts[id] = Contract.create!(tenant: @tenant, source_system: @system, external_id: id, code: code, created_by_omission: false)
          elsif code && contract.code != code
            @changes << [ contract, "updated", { field: "code", before: contract.code, after: code } ]
            contract.update!(code: code)
          end
        end
        contracts
      end

      # Contrato por omissão (MT-14; 17, R404): um por cliente e por sistema, reaproveitado nas cargas seguintes daquele sistema.
      def omission_contracts(rows, customers)
        ids = rows.reject(&:contract).map { |row| customers.fetch(row.document).id }.uniq
        return {} if ids.empty?

        found = Contract.where(tenant_id: @import.tenant_id, source_system_id: @system.id, created_by_omission: true).joins(:contract_customers).where(contract_customers: { customer_id: ids })
                        .select("contracts.*, contract_customers.customer_id AS owner_id").order(:id).to_a.group_by(&:owner_id).transform_values(&:first)
        customers.each_value do |customer|
          next unless ids.include?(customer.id) && !found.key?(customer.id)

          # A ligação deste contrato nasce em `write_bills`, como as dos contratos declarados: todo cliente aqui tem ao menos uma linha sem contrato.
          found[customer.id] = Contract.create!(tenant: @tenant, source_system: @system, code: nil, created_by_omission: true)
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

      # R9b: a união do que as linhas declaram (coluna vazia vale os dois papéis), somada ao que o cliente já tinha; uma carga nunca remove papel. A
      # ligação nova vai ao banco num só INSERT, já com os papéis; a de um cliente cujas linhas caíram no R57 fica sem papel. A ligação guarda a
      # identidade remota usada naquele contrato, a mais recente que chegou (17, R409).
      def write_roles(entries, links)
        entries.group_by { |entry| [ entry.contract.id, entry.customer.id ] }.each do |key, group|
          declared = []
          declared << "holder" if group.any? { |entry| entry.row.roles.nil? || entry.row.roles.include?("holder") }
          declared << "financial_responsible" if group.any? { |entry| entry.row.roles.nil? || entry.row.roles.include?("financial_responsible") }
          link = links.fetch(key)
          link.roles = (link.roles | declared).sort
          identity = group.reverse_each.lazy.filter_map { |entry| @identities[entry.row.line] }.first
          link.customer_identity = identity if identity
        end
        links.each_value { |link| link.save! if link.new_record? || link.changed? }
      end

      # R13: valor, vencimento, contrato e descrição de título existente são atualizados, com registro. R16: título retirado que volta fica ativo, com o
      # registro "retirado em X, reincluído em Y". Em id próprio (17, R405), o número também é dado que a carga atualiza, e o título com a troca de
      # devedor confirmada passa ao cliente da linha; o registro guarda os ids dos clientes, nunca nome nem documento.
      def write_bill(entry)
        row = entry.row
        bill = entry.bill
        if bill.nil?
          entry.bill = Bill.new(tenant: @tenant, source_system: @system, external_id: (row.external_bill_id if @own_id), contract: entry.contract, customer: entry.customer,
                                number: row.number, due_date: row.due_date, amount_cents: entry.amount_cents,
                                description: row.description, product: row.product, status: "active", last_import_id: @import.id, version_user: @decider)
          entry.bill.save!
          return
        end

        entry.before_amount = bill.amount_cents
        fields = { amount_cents: entry.amount_cents, due_date: row.due_date, description: row.description }
        fields[:number] = row.number if @own_id
        fields.each do |field, value|
          @changes << [ bill, "updated", { field: field.to_s, before: bill[field]&.to_s, after: value&.to_s } ] if bill[field] != value
        end
        if bill.contract_id != entry.contract.id
          @changes << [ bill, "updated", { field: "contract", before: bill.contract.code, after: entry.contract.code } ]
        end
        if bill.customer_id != entry.customer.id
          @changes << [ bill, "customer_changed", { field: "customer", before: bill.customer_id.to_s, after: entry.customer.id.to_s, origin: "load" } ]
        end
        @changes << [ bill, "reincluded", { field: "status", before: "withdrawn", after: "active" } ] if bill.withdrawn?
        bill.update!(contract: entry.contract, customer: entry.customer, number: row.number, due_date: row.due_date, amount_cents: entry.amount_cents, description: row.description, product: row.product || bill.product,
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
