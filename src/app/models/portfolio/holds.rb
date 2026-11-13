module Portfolio
  # Mudanças a confirmar (17, R405, R408, R409a, SI8): a linha que troca o devedor de um título do sistema (o mesmo `id_titulo` com outro documento) e
  # a linha cujo `id_cliente` já é de outro documento ficam seguras até o gestor confirmar, item a item ou todas. A conferência as marca na
  # preparação (`import_rows.hold_kind`), a tela grava a confirmação de cada uma (`hold_confirmed`) e, na hora de confirmar a importação, as que
  # ficaram sem confirmação deixam de ser linha válida: não são aplicadas, vão ao resultado como ignoradas e, por continuarem na preparação, não
  # são retiradas no batimento (R15). Título com promessa ou acordo em aberto não pode ser confirmado.
  class Holds
    # Itens mostrados na conferência.
    LIMIT = 200
    SLICE = 1_000
    PROMISE = "título com promessa em aberto".freeze
    AGREEMENT = "título com acordo em aberto".freeze
    UNCONFIRMED = { "debtor" => "troca de devedor não confirmada; o título ficou como estava",
                    "identity" => "id de cliente com outro documento, não confirmado; a linha não foi aplicada",
                    "both" => "troca de devedor e id de cliente com outro documento, não confirmados; a linha não foi aplicada" }.freeze

    DEBTOR = %w[debtor both].freeze
    IDENTITY = %w[identity both].freeze

    # Linha segura da lista: a linha da preparação, o cliente que hoje tem o título e o que hoje tem o id de cliente.
    Item = Struct.new(:row, :debtor, :identity_owner)

    Counts = Struct.new(:total, :blocked, :confirmed) do
      def pending = total - blocked - confirmed
      def unapplied = total - confirmed
    end

    # O motivo que impede a troca de devedor de cada título (R409a): só os que têm motivo aparecem.
    def self.blocked_reasons(bill_ids)
      return {} if bill_ids.empty?

      reasons = AgreementBill.where(bill_id: bill_ids, held: true).pluck(:bill_id).index_with { AGREEMENT }
      reasons.merge(PaymentPromiseBill.where(bill_id: bill_ids, held: true).pluck(:bill_id).index_with { PROMISE })
    end

    def initialize(import)
      @import = import
      @matching = Matching.new(import)
    end

    # Etapa da conferência: marca as linhas válidas com mudança a confirmar e devolve as contagens do resumo.
    def detect
      found = Hash.new { |hash, line| hash[line] = { identity: false, debtor: false, reason: nil } }
      identity_lines.each { |line| found[line][:identity] = true }
      debtors = debtor_lines
      debtors.each_slice(SLICE) do |slice|
        reasons = self.class.blocked_reasons(slice.map(&:last))
        slice.each { |line, bill_id| found[line].merge!(debtor: true, reason: reasons[bill_id]) }
      end
      found.group_by { |_, hold| [ kind_of(hold), hold[:reason] ] }.each do |(kind, reason), group|
        group.map(&:first).each_slice(SLICE) { |lines| ImportRow.where(import_id: @import.id, line: lines).update_all(hold_kind: kind, hold_blocked_reason: reason) }
      end
      { count: found.size, blocked: found.count { |_, hold| hold[:reason] } }
    end

    def counts
      total, blocked, confirmed = held.pick(Arel.sql("count(*)"), Arel.sql("count(hold_blocked_reason)"), Arel.sql("count(*) filter (where hold_confirmed)"))
      Counts.new(total.to_i, blocked.to_i, confirmed.to_i)
    end

    # As primeiras linhas seguras, na ordem do arquivo.
    def items(limit = LIMIT) = held.order(:line).limit(limit).to_a

    # As linhas seguras como a conferência as mostra: com o cliente que hoje tem o título e o que hoje tem o id de cliente. Duas consultas para a
    # lista inteira, pelos índices `bills (tenant_id, source_system_id, external_id) WHERE external_id IS NOT NULL` e `customer_identities
    # (tenant_id, external_id, source_system_id)`.
    def listing(limit = LIMIT)
      rows = items(limit)
      scope = { tenant_id: @import.tenant_id, source_system_id: @import.source_system_id }
      bill_ids = rows.select { |row| DEBTOR.include?(row.hold_kind) }.filter_map(&:external_bill_id)
      debtors = bill_ids.empty? ? {} : Bill.where(scope).where.not(external_id: nil).where(external_id: bill_ids).joins(:customer).pluck("bills.external_id", "customers.name").to_h
      customer_ids = rows.select { |row| IDENTITY.include?(row.hold_kind) }.filter_map(&:external_customer_id)
      owners = customer_ids.empty? ? {} : CustomerIdentity.where(scope).where(external_id: customer_ids).joins(:customer).pluck("customer_identities.external_id", "customers.name").to_h
      rows.map { |row| Item.new(row, (debtors[row.external_bill_id] if DEBTOR.include?(row.hold_kind)), (owners[row.external_customer_id] if IDENTITY.include?(row.hold_kind))) }
    end

    # R409a: confirma uma mudança (`line`) ou todas as que podem ser confirmadas. Devolve quantas mudaram.
    def confirm(line = nil) = mark(line, true)

    def undo(line = nil) = mark(line, false)

    # Na confirmação da importação: a linha segura que não foi confirmada sai das válidas e entra no resultado como ignorada, com os contatos que
    # trazia. Devolve as contagens do que será e do que não será aplicado.
    def settle
      pending = held.where(hold_confirmed: false).order(:line).pluck(:line, :hold_kind, :hold_blocked_reason)
      confirmed = held.where(hold_confirmed: true).count
      pending.each_slice(SLICE) do |slice|
        lines = slice.map(&:first)
        ImportRejection.insert_all!(slice.map { |line, kind, reason| { import_id: @import.id, line: line, reason: reason ? "troca de devedor não aplicada: #{reason}" : UNCONFIRMED.fetch(kind), ignored: true } })
        ImportContact.where(import_id: @import.id, line: lines).delete_all
        ImportRow.where(import_id: @import.id, line: lines).update_all(ok: false)
      end
      { confirmed: confirmed, unapplied: pending.size }
    end

    private
      # A passagem é pela chave primária da preparação (`import_id`, `line`): quem chama já sabe, pelo resumo, que há linha segura.
      def held = ImportRow.where(import_id: @import.id).where.not(hold_kind: nil)

      def mark(line, value)
        scope = held.where(hold_blocked_reason: nil, hold_confirmed: !value)
        scope = scope.where(line: line) if line
        scope.update_all(hold_confirmed: value)
      end

      def kind_of(hold) = hold[:identity] && hold[:debtor] ? "both" : (hold[:debtor] ? "debtor" : "identity")

      # R408: o id de cliente da linha já é, neste sistema, de um cliente de outro documento. Índice `customer_identities (tenant_id, external_id,
      # source_system_id)`.
      def identity_lines
        Sql.rows(<<~SQL, @import.id, @import.tenant_id, @import.source_system_id).map { |row| row["line"] }
          select r.line
          from import_rows r
          join customer_identities i on i.external_id = r.external_customer_id
          join customers c on c.id = i.customer_id
          where r.import_id = ? and r.ok and r.external_customer_id is not null and i.tenant_id = ? and i.source_system_id = ? and c.document <> r.document
        SQL
      end

      # R405: em id próprio, o título do sistema que a linha traz é de um cliente de outro documento. O pago e o renegociado ficam fora: a carga não
      # os atualiza (R57). Índice `bills (tenant_id, source_system_id, external_id) WHERE external_id IS NOT NULL`.
      def debtor_lines
        return [] unless @matching.own_id?

        Sql.rows(<<~SQL, @import.id).map { |row| [ row["line"], row["bill_id"] ] }
          select r.line, b.id as bill_id
          from import_rows r
          join bills b on #{@matching.system_bills} and b.external_id = r.external_bill_id
          join customers c on c.id = b.customer_id
          where r.import_id = ? and r.ok and c.document <> r.document and b.status in ('active', 'withdrawn')
        SQL
      end
  end
end
