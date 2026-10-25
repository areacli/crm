module Demo
  # Arquivos fictícios que a demonstração usa no lugar do que o visitante envia: o dele é descartado sem ser lido (LGPD). Cada método devolve o caminho de
  # um CSV temporário, que quem chama apaga depois de enviá-lo ao serviço de importação.
  module Files
    NAME = "arquivo-de-demonstracao.csv".freeze

    module_function

    def for(kind, tenant)
      case kind.to_s
      when "payments" then payments(tenant)
      when "reversals" then reversals(tenant)
      else portfolio
      end
    end

    # Cem clientes que já estão na carteira (idênticos, sem mudança) e cem novos.
    def portfolio
      PortfolioSheet.write(temporary("carteira"), (Demo.customers - 100)...(Demo.customers + 100))
    end

    # Pagamentos dos títulos em cobrança do dia: quitam, pagam metade, pagam a mais, e uma linha de título que não existe.
    def payments(tenant)
      channel = tenant.payment_channels.where(active: true).order(:id).first
      stamp = Time.current.strftime("%Y%m%d%H%M%S")
      rows = [ "canal;identificador;documento;titulo;data_pagamento;valor;meio" ]
      Bill.where(tenant_id: tenant.id, status: "active").where("paid_cents = 0").includes(:customer).order(id: :desc).limit(30).each_with_index do |bill, index|
        cents = case index % 3
        when 0 then bill.amount_cents
        when 1 then bill.amount_cents / 2
        else bill.amount_cents + 1_500
        end
        rows << [ channel&.code, "V#{stamp}#{index}", bill.customer.document, bill.number, Date.current.strftime("%d/%m/%Y"), Money.format(cents), "pix" ].join(";")
      end
      rows << [ channel&.code, "V#{stamp}X", FakeData.cpf(3), "NF-9999/1", Date.current.strftime("%d/%m/%Y"), "200,00", "pix" ].join(";")
      write("pagamentos", rows)
    end

    # Estornos parciais de pagamentos já aplicados do credor.
    def reversals(tenant)
      stamp = Time.current.strftime("%Y%m%d%H%M%S")
      rows = [ "canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo" ]
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
