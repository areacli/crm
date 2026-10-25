module Demo
  class Dataset
    # Acionamentos em volume, situação dos contatos, divergências de valor, correção de índice e a importação à espera de confirmação.
    module ActivitySteps
      private
        # Divergências de valor (05): uma nova carga muda o valor de títulos que já existem (alguns já com pagamento), e a política "seguir o valor novo" aplica.
        def discrepancies(tenant)
          seeds = (200...400).select { |seed| (seed % 3).zero? }
          path = @tmp.join("divergencias-#{tenant.id}.csv").to_s
          rows = seeds.map do |seed|
            cells = PortfolioSheet.lines(seed, today).first
            index = PortfolioSheet::HEADER.index("valor")
            cents = Money.parse_cents(cells[index]).first
            cells[index] = Money.format(seed.even? ? cents + 3_500 : cents - 1_200)
            cells.join(";")
          end
          File.write(path, "#{PortfolioSheet::HEADER.join(';')}\r\n#{rows.join("\r\n")}\r\n")
          run_import(tenant, path, name: "carteira-revisada.csv")
        end

        # 30 mil acionamentos dos últimos 120 dias entre os 12 resultados, os canais e os dois usuários; cerca de 150 contatos marcados como inválidos ou
        # "não perturbe"; uma correção de índice do credor.
        def attempts(tenant, total: 30_000)
          results = ContactResult.where(tenant_id: tenant.id).order(:position).to_a
          customer_ids = Customer.where(tenant_id: tenant.id).order(:id).pluck(:id)
          users = tenant.memberships.pluck(:user_id)
          now = Time.current
          rows = []
          total.times do |i|
            result = results[i % results.size]
            when_at = now - (i % 120).days - ((i * 37) % 600).minutes
            channel = %w[phone phone whatsapp sms email letter in_person][i % 7]
            rows << { tenant_id: tenant.id, customer_id: customer_ids[(i * 7) % customer_ids.size], user_id: users[i % users.size], result_id: result.id,
                      result_kind: result.kind, channel: channel, contact_used: (People.phone(i) if %w[phone whatsapp sms].include?(channel)),
                      text: (i % 4).zero? ? "Texto fictício da demonstração." : nil, contacted_at: when_at, return_at: (when_at + 3.days if result.return_required? && i % 3 != 0),
                      created_at: when_at, updated_at: when_at }
            if rows.size >= 2_000
              ContactAttempt.insert_all!(rows)
              rows = []
            end
          end
          ContactAttempt.insert_all!(rows) if rows.any?
          return unless tenant.id == @alpha&.id

          editor = Registry::ContactEditor.new(@manager)
          CustomerContact.where(tenant_id: tenant.id, kind: "phone", status: "valid").order(:id).limit(900).each_with_index do |contact, index|
            next unless (index % 6).zero?

            if (index % 12).zero?
              editor.do_not_disturb(contact, today - 2 - index % 20, "Pediu para não receber ligações.")
            else
              editor.mark_invalid(contact, "Número não pertence mais ao cliente.")
            end
          end
          IndexAdjustment.create!(tenant_id: tenant.id, user: @manager, series: "ipca", month: today.beginning_of_month.prev_month, value: BigDecimal("0.48"),
                                  reason: "Valor divulgado depois da busca automática.", adjusted_at: Time.current)
        end

        # Uma carga conferida e à espera de confirmação, com linhas recusadas, para mostrar a conferência (ocupa o credor até alguém confirmar ou descartar).
        def pending_import(tenant)
          path = @tmp.join("batimento-#{tenant.id}.csv").to_s
          header = PortfolioSheet::HEADER
          lines = (0...200).flat_map { |seed| PortfolioSheet.lines(seed, today) }.map { |cells| cells.join(";") }
          bad = ->(overrides) { header.map { |column| overrides[column].to_s }.join(";") }
          lines << bad.call("documento" => "111.111.111-11", "nome" => "Fulano de Tal", "titulo" => "NF-9001", "vencimento" => "10/09/2026", "valor" => "250,00")
          lines << bad.call("documento" => "529.982.247-25", "nome" => "Maria da Silva", "contrato" => "CT-9", "titulo" => "NF-9002", "vencimento" => "31/02/2026", "valor" => "250,00")
          lines << bad.call("documento" => "390.533.447-05", "nome" => "João Souza", "contrato" => "CT-9", "titulo" => "NF-9003", "vencimento" => "10/09/2026", "valor" => "12,345")
          File.write(path, "#{header.join(';')}\r\n#{lines.join("\r\n")}\r\n")
          run_import(tenant, path, name: "batimento-outubro.csv", confirm: false)
        end
    end
  end
end
