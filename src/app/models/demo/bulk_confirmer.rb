module Demo
  # Gravação da carga inicial da demonstração: o mesmo arquivo passa pela conferência de sempre (leitura, validação, preparação), mas a confirmação grava a
  # massa de dados fictícia por `insert_all!` dos modelos em fatias de clientes, em vez de `create!` por registro (decisão 0021, parte 2: onde não é o fluxo
  # que a demonstração mostra, a massa entra em lote; o fluxo completo continua nos cenários exemplares, na carga que o visitante envia e nos pagamentos).
  # Serve só para carga em credor vazio (todos os clientes são novos): é o que a recriação diária faz. O resultado é o mesmo da confirmação normal:
  # clientes, contatos, contratos declarados, ligações com papéis, títulos, versão 1 do valor e acréscimos informados (teste em `bulk_confirmer_test`).
  class BulkConfirmer < Portfolio::ImportConfirmer
    CUSTOMERS_PER_SLICE = 2_000

    private
      def write_portfolio(import, _step)
        tenant_id = import.tenant_id
        accepted = ImportRow.where(import_id: import.id, ok: true)
        raise "a carga em massa da demonstração exige credor sem clientes" if Customer.exists?(tenant_id: tenant_id)
        raise "a carga em massa da demonstração exige contrato em toda linha" if accepted.where(contract: nil).exists?

        decider = import.confirmed_by || import.user
        documents = accepted.distinct.order(:document).pluck(:document)
        documents.each_slice(CUSTOMERS_PER_SLICE).with_index do |slice, index|
          ApplicationRecord.transaction { write_slice(import, decider, slice) }
          import.update!(progress_percent: 1 + (73 * ((index + 1) * CUSTOMERS_PER_SLICE).clamp(0, documents.size) / documents.size), progress_label: "Gravando a carteira")
        end
      end

      def write_slice(import, decider, documents)
        tenant_id = import.tenant_id
        now = Time.current
        rows = ImportRow.where(import_id: import.id, ok: true, document: documents).order(:line).to_a
        names = rows.group_by(&:document).transform_values { |lines| lines.max_by(&:line).name }
        customers = Customer.insert_all!(documents.map { |document| { tenant_id: tenant_id, document: document, name: names.fetch(document) } },
                                         returning: %w[id document]).rows.to_h { |id, document| [ document, id ] }
        write_contacts(import, customers, now)
        contracts = write_contracts(tenant_id, rows)
        write_links(contracts, customers, rows)
        write_bills(import, decider, customers, contracts, rows)
      end

      def write_contacts(import, customers, now)
        seen = Set.new
        rows = ImportContact.where(import_id: import.id, document: customers.keys).order(:line).filter_map do |contact|
          customer_id = customers.fetch(contact.document)
          next unless seen.add?([ customer_id, contact.kind, contact.key ])

          { tenant_id: import.tenant_id, customer_id: customer_id, kind: contact.kind, key: contact.key, value: contact.value, street: contact.street, number: contact.number,
            complement: contact.complement, district: contact.district, city: contact.city, state: contact.state, zip: contact.zip, origin: "load",
            status: contact.tenant_contact ? "invalid" : "valid", reason: (contact.tenant_contact ? "é contato do credor" : nil), kept_by_tenant: false, seen_in_import_at: now }
        end
        CustomerContact.insert_all!(rows, returning: false) if rows.any?
      end

      # Contratos declarados (um contrato pode ser de clientes de fatias diferentes: o que já existe é reaproveitado).
      def write_contracts(tenant_id, rows)
        codes = rows.map(&:contract).uniq
        found = Contract.where(tenant_id: tenant_id, code: codes).pluck(:code, :id).to_h
        missing = codes - found.keys
        found.merge!(Contract.insert_all!(missing.map { |code| { tenant_id: tenant_id, code: code, created_by_omission: false } }, returning: %w[code id]).rows.to_h) if missing.any?
        found
      end

      # R9b: a união do que as linhas declaram (coluna vazia vale os dois papéis).
      def write_links(contracts, customers, rows)
        links = rows.group_by { |row| [ row.contract, row.document ] }.map do |(code, document), group|
          declared = []
          declared << "holder" if group.any? { |row| row.roles.nil? || row.roles.include?("holder") }
          declared << "financial_responsible" if group.any? { |row| row.roles.nil? || row.roles.include?("financial_responsible") }
          { contract_id: contracts.fetch(code), customer_id: customers.fetch(document), roles: declared.sort }
        end
        ContractCustomer.insert_all!(links, returning: false)
      end

      def write_bills(import, decider, customers, contracts, rows)
        tenant_id = import.tenant_id
        ids = Bill.insert_all!(rows.map do |row|
          { tenant_id: tenant_id, contract_id: contracts.fetch(row.contract), customer_id: customers.fetch(row.document), number: row.number, due_date: row.due_date, amount_cents: row.amount_cents,
            description: row.description, product: row.product, status: "active", last_import_id: import.id }
        end, returning: %w[id customer_id number]).rows.to_h { |id, customer_id, number| [ [ customer_id, number ], id ] }
        BillValueVersion.insert_all!(rows.map do |row|
          { tenant_id: tenant_id, bill_id: ids.fetch([ customers.fetch(row.document), row.number ]), amount_cents: row.amount_cents, import_id: import.id, user_id: decider&.id }
        end, returning: false)
        surcharges = rows.reject { |row| [ row.penalty_cents, row.interest_cents, row.correction_cents, row.other_cents ].all?(&:nil?) }
        return if surcharges.empty?

        ReportedSurcharge.insert_all!(surcharges.map do |row|
          { tenant_id: tenant_id, bill_id: ids.fetch([ customers.fetch(row.document), row.number ]), import_id: import.id, penalty_cents: row.penalty_cents.to_i,
            interest_cents: row.interest_cents.to_i, correction_cents: row.correction_cents.to_i, other_cents: row.other_cents.to_i }
        end, returning: false)
      end
  end
end
