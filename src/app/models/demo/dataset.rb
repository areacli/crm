require "active_support/testing/time_helpers"

module Demo
  # Os dados fictícios da demonstração (CRM_DEMO=1) e das capturas de tela. Dois credores: "Escola Alfa", com a carteira grande (10 mil clientes, títulos
  # desde 2020 em todas as faixas de atraso, pagamentos, estornos, acionamentos, promessas nos oito estados, acordos, divergências, instrumentos de
  # pagamento do fornecedor falso e um link de pagamento), e "Clínica Beta", pequena, para mostrar o isolamento por credor. O gestor público tem um
  # perfil em cada credor (Gestor demonstração na Alfa, Operador na Beta); o operador público só enxerga a Alfa.
  #
  # Tudo passa pelos mesmos serviços do produto (importação, acionamento, promessa, acordo, anonimização, emissão), com SQL de conjunto onde o volume pede
  # (carga de 20 mil linhas, 30 mil acionamentos). Nada chama a internet: o fornecedor de pagamento é o falso e os índices vêm de `Demo::IndexClient`.
  class Dataset
    include ActiveSupport::Testing::TimeHelpers
    include ActivitySteps
    include PromiseSteps
    include AgreementSteps
    include TitularSteps
    include InstrumentSteps

    ALPHA = "Escola Alfa".freeze
    BETA = "Clínica Beta".freeze
    CHANNELS = { "pix" => [ "341-1234-56789", :account, "Itaú, conta principal" ], "boleto" => [ "2847193", :agreement, "Convênio de cobrança, Bradesco" ],
                 "cartão de crédito" => [ "1029384756", :card, "Cielo, loja virtual" ], "transferência" => [ "341-1234-56789", :account, nil ] }.freeze
    AGREEMENT_VARIABLES = {
      agreement_caps: { "installment" => { "fine" => 100, "interest" => 100, "fees" => 50 }, "cash" => { "fine" => 100, "interest" => 100, "fees" => 50, "correction" => 30 } },
      agreement_max_installments: 12, agreement_min_installment_cents: 10_000, agreement_min_down_payment_pct: 10, agreement_down_payment_days: 10,
      agreement_validity_days: 5, agreement_tolerance_days: 3, agreement_break_days: 30
    }.freeze

    attr_reader :log, :today

    def initialize(customers: Demo.customers, log: nil)
      @customers = customers
      @log = log || ->(_message) { }
    end

    # Cria tudo e devolve os credores. Roda no banco como está (a recriação, `Demo::Reset`, esvazia antes).
    def call(today: Date.current)
      @today = today
      @tmp = Rails.root.join("tmp", "demo-#{Process.pid}")
      FileUtils.mkdir_p(@tmp)
      with_jobs_discarded do
        users
        step("Índices") { Indexes::Fetch.new.call(today: today) }
        alpha = step("Credor #{ALPHA}") { build_alpha }
        beta = step("Credor #{BETA}") { build_beta }
        [ alpha, beta ]
      end
    ensure
      FileUtils.rm_rf(@tmp) if @tmp
    end

    private
      def step(name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        log.call(format("%-40s %6.1f s", name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started))
        result
      end

      # As filas ficam de fora: cada passo roda o que precisa na hora, na ordem certa (conferir, confirmar, recalcular).
      def with_jobs_discarded
        previous = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :test
        yield
      ensure
        ActiveJob::Base.queue_adapter = previous
      end

      # --- Usuários públicos: senhas legíveis e fixas; a recriação as restaura e tira qualquer bloqueio. Os usuários sobrevivem à recriação
      # (as sessões abertas continuam valendo).
      def users
        @manager = public_user("gestor", "Gestor da demonstração")
        @operator = public_user("operador", "Operador da demonstração")
      end

      def public_user(who, name)
        user = User.find_or_initialize_by(email_address: Demo.email(who))
        user.name = name
        user.password = Demo.password(who)
        user.active = true
        user.failed_attempts = 0
        user.locked_until = nil
        user.temporary_password_until = nil
        user.save!(validate: false)
        user
      end

      def link(user, tenant, profile_name)
        Membership.create!(user: user, tenant: tenant, profile: tenant.profiles.find_by!(name: profile_name), active: true)
      end

      def build_alpha
        tenant = Tenant.provision!(ALPHA, cnpj: "11222333000181", legal_name: "Escola Alfa Educação Ltda")
        registry(tenant, trade_name: "Escola Alfa", street: "Avenida Paulista", number: "1000", district: "Bela Vista", city: "São Paulo", state: "SP", zip: "01310100",
                         email: "cobranca@escolaalfa.exemplo.com.br", phone: "(11) 3333-4444")
        gestor = tenant.profiles.create!(name: "Gestor demonstração", permissions: Permission::ALL - %w[manage_users manage_profiles])
        link(@manager, tenant, gestor.name)
        link(@operator, tenant, "Operador")
        @alpha = tenant
        channels(tenant)
        configure(tenant)
        step("  carteira (#{@customers} clientes)") { portfolio(tenant, 0...@customers, name: "carteira-outubro.csv") }
        step("  segmentos e valores atualizados") { recalc(tenant) }
        step("  pagamentos e estornos") { payments(tenant) }
        step("  divergências de valor") { discrepancies(tenant) }
        step("  acionamentos e cadastros") { attempts(tenant) }
        step("  promessas") { promises(tenant) }
        step("  acordos") { agreements(tenant) }
        step("  direitos do titular") { titular(tenant) }
        step("  instrumentos e link de pagamento") { instruments(tenant) }
        step("  importação à espera de confirmação") { pending_import(tenant) }
        recalc(tenant)
        tenant
      end

      def build_beta
        tenant = Tenant.provision!(BETA, cnpj: "11444777000161", legal_name: "Clínica Beta Saúde Ltda")
        registry(tenant, trade_name: "Clínica Beta", street: "Rua XV de Novembro", number: "250", district: "Centro", city: "Curitiba", state: "PR", zip: "80020310",
                         email: "financeiro@clinicabeta.exemplo.com.br", phone: "(41) 3222-1000")
        link(@manager, tenant, "Operador")
        channel = PaymentChannel.create!(tenant: tenant, kind: :account, code: "001-4455-90210", description: "Banco do Brasil, conta da clínica")
        tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, charge_index: "ipca")
        Segment.catch_all_of(tenant).update!(interest_kind: "fixed")
        Charges::RuleHistory.record!(tenant, since: Date.new(2020, 1, 1))
        portfolio(tenant, 20_000...20_000 + [ @customers / 16, 40 ].max, name: "carteira-clinica.csv")
        recalc(tenant)
        payments(tenant, codes: CHANNELS.keys.index_with { channel.code }, share: 30)
        attempts(tenant, total: 600)
        recalc(tenant)
        tenant
      end

      # Contratos de um só cliente com títulos em aberto, vencidos há mais de `older_than` dias, sem pagamento nem promessa nem acordo: a matéria-prima dos
      # cenários. Devolve [{ customer:, contract:, bills: [..] }], dos clientes de número mais alto para os mais baixos (os baixos têm as divergências).
      def candidates(tenant, count, min_bills: 1, older_than: 20)
        @used ||= Set.new
        rows = Portfolio::Sql.rows(<<~SQL, tenant.id, today - older_than, min_bills, count + @used.size + 20)
          select b.customer_id, b.contract_id, array_agg(b.id order by b.due_date, b.id) as ids
          from bills b
          where b.tenant_id = ? and b.status = 'active' and b.paid_cents = 0 and b.kind = 'common' and b.due_date < ?::date
            and (select count(*) from contract_customers cc where cc.contract_id = b.contract_id) = 1
            and not exists (select 1 from payments py where py.bill_id = b.id)
            and not exists (select 1 from payment_promise_bills pb where pb.bill_id = b.id) and not exists (select 1 from agreement_bills ab where ab.bill_id = b.id)
          group by b.customer_id, b.contract_id having count(*) >= ?
          order by b.customer_id desc limit ?
        SQL
        picked = rows.reject { |row| @used.include?(row["customer_id"].to_i) }.first(count)
        picked.each { |row| @used << row["customer_id"].to_i }
        ids = picked.flat_map { |row| row["ids"].to_s.delete("{}").split(",").map(&:to_i) }
        bills = Bill.where(id: ids).index_by(&:id)
        picked.map do |row|
          { customer: Customer.find(row["customer_id"]), contract: Contract.find(row["contract_id"]), bills: row["ids"].to_s.delete("{}").split(",").map { |id| bills.fetch(id.to_i) } }
        end
      end

      # Cria cada cenário com o primeiro candidato que a regra do produto aceitar (a carga tem datas relativas a hoje, e um candidato pode não servir num dia
      # qualquer: parcela mínima, título já preso por outra proposta). Esgotados os candidatos, falha com o motivo da última recusa.
      def first_that_works(sources, &block)
        last = nil
        while (source = sources.shift)
          begin
            return block.call(source)
          rescue Agreements::Refused, Promises::Refused, Contacts::Refused => error
            last = error
          end
        end
        raise last || "sem candidatos para o cenário"
      end

      def registry(tenant, **fields)
        tenant.assign_attributes(fields)
        tenant.save!(context: :registry)
      end

      def with_import_user(tenant) = tenant.memberships.joins(:profile).order(:id).first.user

      # Envia, confere e confirma uma carga como a tela faria (as filas ficam de fora).
      def run_import(tenant, path, kind: "portfolio", mode: :incremental, name: nil, confirm: true)
        service = Portfolio::ImportService.new
        import = service.start(tenant: tenant, user: with_import_user(tenant), file: path, mode: mode, original_name: name || File.basename(path), kind: kind)
        import.checker.run(import)
        import.reload
        raise "importação #{kind} recusada: #{import.summary.inspect[0, 300]}" if import.rejected? || import.failed?
        return import unless confirm

        import.confirmer.run(import)
        import.reload
        raise "confirmação #{kind} falhou: #{import.status}" unless import.confirmed?

        import
      end

      def portfolio(tenant, range, name:)
        path = PortfolioSheet.write(@tmp.join("#{name}-#{tenant.id}").to_s, range, today: today)
        run_import(tenant, path, name: name)
      end

      def recalc(tenant)
        Segments::Recalculation.new(tenant).apply(today: today)
        Charges::Recalculation.new(tenant).apply(today: today)
      end

      # Canais de recebimento e as contas do fornecedor falso (nada de segredo real: a chave é uma frase fixa de demonstração).
      def channels(tenant)
        @channels = CHANNELS.values.uniq { |code, _, _| code }.to_h do |code, kind, description|
          [ code, PaymentChannel.create!(tenant: tenant, kind: kind, code: code, description: description || "Conta #{code}") ]
        end
        pix_channel = @channels["341-1234-56789"]
        { "boleto" => @channels["2847193"], "pix" => pix_channel, "card" => @channels["1029384756"] }.each do |modality, channel|
          account = tenant.payment_accounts.build(channel: channel, modality: modality, provider: "fake", environment: "production", active: true,
                                                   nickname: "#{{ 'boleto' => 'Boleto', 'pix' => 'Pix', 'card' => 'Cartão' }.fetch(modality)} (fornecedor de demonstração)")
          account.assign_values(config: { "connection_result" => "ok", "pix_key" => "pagamentos@escolaalfa.exemplo.com.br", "max_installments" => 6 },
                                secrets: { "api_key" => "chave-fictícia-de-demonstração" })
          account.save!
        end
      end

      # Encargos (multa 2%, juros de 1% ao mês, IPCA), segmentos com critérios, variáveis de acordo e as alçadas.
      def configure(tenant)
        tenant.setting.update!(charge_fine_pct: 2, charge_interest_pct: 1, charge_index: "ipca", installment_rate_pct: 1.5, installment_method: "price")
        catch_all = Segment.catch_all_of(tenant)
        catch_all.update!(interest_kind: "fixed", **AGREEMENT_VARIABLES)
        [ [ "Mensalidade recente", { products: [ "Mensalidade" ], max_overdue_days: 90 } ], [ "Cartão de crédito", { products: [ "Cartão de crédito" ] } ],
          [ "Pessoa jurídica", { person_type: "company" } ] ].each_with_index do |(name, criteria), index|
          Segment.create!(tenant: tenant, name: name, position: index + 1, interest_kind: "fixed", **criteria, **AGREEMENT_VARIABLES)
        end
        AgreementLimit.where(segment_id: tenant.segments.select(:id)).delete_all
        tenant.segments.find_each { |segment| AgreementLimit.create_for_segment(segment) }
        Charges::RuleHistory.record!(tenant, since: Date.new(2020, 1, 1))
      end

      # Recebimentos: pagam cerca de um terço dos títulos vencidos há mais de 15 dias (quitam, pagam metade, pagam a mais, parcial de 30%), com uma
      # linha repetida e linhas de título que não existe (ficam pendentes). Depois, estornos de alguns pagamentos aplicados.
      def payments(tenant, codes: CHANNELS.transform_values(&:first), share: 38)
        # O pagamento baixa primeiro os encargos (baixa por componente, 09): quem quita paga o valor atualizado de hoje, que a tabela de valores guarda.
        bills = Bill.where(tenant_id: tenant.id).joins(:customer).joins("left join bill_valuations on bill_valuations.bill_id = bills.id").where("bills.due_date < ?", today - 15).order(:id)
                    .pluck("customers.document", :number, Arel.sql("coalesce(bill_valuations.total_cents, bills.amount_cents)"), :due_date, :id)
        lines = [ %w[canal identificador documento titulo data_pagamento valor meio] ]
        methods = %w[pix boleto cartão\ de\ crédito transferência]
        bills.each do |document, number, cents, due, id|
          roll = Zlib.crc32("pay:#{id}") % 100
          next unless roll < share

          kind = Zlib.crc32("how:#{id}") % 100
          value = case kind
          when 0...60 then cents
          when 60...78 then cents / 2
          when 78...88 then cents + 2_500
          else cents * 3 / 10
          end
          method = methods[id % 4]
          date = kind < 60 ? today - 1 - (Zlib.crc32("when:#{id}") % 20) : [ due + (Zlib.crc32("when:#{id}") % 26), today - 1 ].min
          lines << [ codes.fetch(method), "P#{id}", document, number, date.strftime("%d/%m/%Y"), Money.format(value), method ]
        end
        # Três clientes com tudo a vencer e pago em dia, sem crédito nem saldo: são os que a anonimização a pedido aceita (07, R130).
        Portfolio::Sql.rows(<<~SQL, tenant.id, today, 3).each do |row|
          select c.document, b.number, b.amount_cents, b.id from bills b join customers c on c.id = b.customer_id
          where b.tenant_id = ? and b.customer_id in (
            select customer_id from bills where tenant_id = b.tenant_id group by customer_id having min(due_date) >= ?::date and count(*) <= 2 order by customer_id desc limit ?)
        SQL
          lines << [ codes.fetch("pix"), "Q#{row['id']}", row["document"], row["number"], (today - 1).strftime("%d/%m/%Y"), Money.format(row["amount_cents"].to_i), "pix" ]
        end
        duplicate = lines[1]
        lines << duplicate.dup
        40.times do |n|
          lines << [ codes.fetch("pix"), "PEND#{n}", FakeData.cpf(n * 7), "NF-9999#{n}/1", (today - 1 - n % 20).strftime("%d/%m/%Y"), Money.format(15_000 + n * 1_000), "pix" ]
        end
        path = @tmp.join("pagamentos-#{tenant.id}.csv").to_s
        File.write(path, lines.map { |line| line.join(";") }.join("\n") + "\n")
        run_import(tenant, path, kind: "payments", name: "pagamentos-outubro.csv")
        Charges::Recalculation.new(tenant).apply(today: today)

        applied = Payment.where(tenant_id: tenant.id, status: "applied").where("amount_cents > 3000").joins(:channel).order(:id).limit(2_000)
                         .pluck("payment_channels.code", :identifier, :amount_cents)
        reversals = [ %w[canal identificador_pagamento identificador_estorno data_estorno valor motivo] ]
        applied.each_with_index do |(code, identifier, cents), index|
          next unless (index % 25).zero?

          reversals << [ code, identifier, "E#{identifier}", today.strftime("%d/%m/%Y"), Money.format((index % 50).zero? ? cents : cents / 3),
                         index.even? ? "contestação do pagador" : "pagamento em duplicidade" ]
        end
        path = @tmp.join("estornos-#{tenant.id}.csv").to_s
        File.write(path, reversals.map { |line| line.join(";") }.join("\n") + "\n")
        run_import(tenant, path, kind: "reversals", name: "estornos-outubro.csv")
        Charges::Recalculation.new(tenant).apply(today: today)
      end
  end
end
