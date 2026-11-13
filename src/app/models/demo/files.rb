module Demo
  # Arquivos fictícios que a demonstração usa no lugar do que o visitante envia: o dele é descartado sem ser lido (LGPD). Cada método devolve o caminho de
  # um CSV temporário, que quem chama apaga depois de enviá-lo ao serviço de importação.
  module Files
    NAME = "arquivo-de-demonstracao.csv".freeze

    module_function

    # `system`: o sistema que o visitante escolheu no envio da carteira (17, R400).
    def for(kind, tenant, system = nil)
      case kind.to_s
      when "payments" then payments(tenant)
      when "reversals" then reversals(tenant)
      else portfolio(system)
      end
    end

    # Cem clientes que já estão na carteira (idênticos, sem mudança) e cem novos. Para um sistema de id próprio, a planilha traz os ids dele.
    def portfolio(system = nil)
      return remote_portfolio if system&.key_own_id?

      PortfolioSheet.write(temporary("carteira"), (Demo.customers - 100)...(Demo.customers + 100))
    end

    # Trinta clientes que o sistema de id próprio da demonstração já trouxe (idênticos, sem mudança) e trinta novos.
    def remote_portfolio
      steps = Dataset::SystemSteps
      known = steps.shared_seeds(Demo.customers).first(15) + steps.new_seeds(Demo.customers).first(15)
      fresh = steps.new_seeds(Demo.customers).last + 1
      PortfolioSheet.write_remote(temporary("carteira"), known + (fresh...(fresh + 30)).to_a)
    end

    # Pagamentos dos títulos em cobrança do dia: quitam, pagam metade, pagam a mais, e uma linha de título que não existe. No credor com mais de um sistema
    # (17, R416 e R417), cada linha diz o sistema do título, e a do sistema de id próprio leva o id do título.
    def payments(tenant)
      channel = tenant.payment_channels.where(active: true).order(:id).first
      stamp = Time.current.strftime("%Y%m%d%H%M%S")
      systems = Payments::Systems.new(tenant.id)
      names = systems.multiple? ? SourceSystem.where(tenant_id: tenant.id, status: "active").where.not(role: "crm").order(:id).pluck(:id, :name).to_h : {}
      extra = names.any? ? [ Payments::SheetModel::SYSTEM_COLUMN ] + (systems.own_ids? ? [ Payments::SheetModel::BILL_ID_COLUMN ] : []) : []
      rows = [ (%w[metodo_recebimento identificador documento titulo data_pagamento valor meio] + extra).join(";") ]
      payable(tenant, names.keys).each_with_index do |bill, index|
        cents = case index % 3
        when 0 then bill.amount_cents
        when 1 then bill.amount_cents / 2
        else bill.amount_cents + 1_500
        end
        system = [ names[bill.source_system_id], bill.external_id.to_s ].first(extra.size)
        rows << ([ channel&.code, "V#{stamp}#{index}", bill.customer.document, bill.number, Date.current.strftime("%d/%m/%Y"), Money.format(cents), "pix" ] + system).join(";")
      end
      rows << ([ channel&.code, "V#{stamp}X", FakeData.cpf(3), "NF-9999/1", Date.current.strftime("%d/%m/%Y"), "200,00", "pix" ] + [ names.values.first, "" ].first(extra.size)).join(";")
      write("pagamentos", rows)
    end

    # Trinta títulos em aberto e sem pagamento, os mais novos; com mais de um sistema, repartidos entre os sistemas ativos.
    def payable(tenant, system_ids)
      open = Bill.where(tenant_id: tenant.id, status: "active").where("paid_cents = 0").includes(:customer).order(id: :desc)
      return open.limit(30).to_a if system_ids.empty?

      system_ids.flat_map { |id| open.where(source_system_id: id).limit(30 / system_ids.size).to_a }
    end

    # Estornos parciais de pagamentos já aplicados do credor.
    def reversals(tenant)
      stamp = Time.current.strftime("%Y%m%d%H%M%S")
      rows = [ "metodo_recebimento;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo" ]
      Payment.where(tenant_id: tenant.id, status: "applied").where("reversed_cents < amount_cents").joins(:channel).order(id: :desc).limit(10)
             .pluck("payment_channels.code", :identifier, :amount_cents, :reversed_cents).each_with_index do |(code, identifier, amount, reversed), index|
        rows << [ code, identifier, "R#{stamp}#{index}", Date.current.strftime("%d/%m/%Y"), Money.format([ (amount - reversed) / 3, 1 ].max), "contestação do pagador" ].join(";")
      end
      write("estornos", rows)
    end

    def temporary(prefix) = Rails.root.join("tmp", "#{prefix}-demo-#{SecureRandom.hex(6)}.csv").to_s

    def write(prefix, rows) = temporary(prefix).tap { |path| File.write(path, "#{rows.join("\n")}\n") }
  end
end
