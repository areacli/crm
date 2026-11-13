module Demo
  class Dataset
    # O segundo sistema da Escola Alfa (17): "ERP Acadêmico", de id próprio, ao lado do "Planilha". Entra com uma carteira pequena de cursos livres, metade
    # de clientes que o Planilha já trouxe (cada um vira um cliente só, com a identidade do ERP) e metade de clientes novos; alguns pagamentos pelo id do
    # título, com a coluna `sistema`; e um segmento que seleciona os contratos dele. Com dois sistemas, o envio de carteira pergunta o sistema, a ficha
    # mostra de onde veio cada título e a planilha de pagamentos passa a exigir a coluna `sistema`.
    module SystemSteps
      NAME = "ERP Acadêmico".freeze
      SEGMENT = "Contratos do ERP Acadêmico".freeze
      NEW_SEEDS = 30_000

      # Clientes de cada metade: 75 com os 10 mil da demonstração, 10 no mínimo (testes).
      def self.half(customers) = [ customers * 3 / 400, 10 ].max

      # Os que o Planilha já trouxe (do meio da carteira) e os que só o ERP conhece.
      def self.shared_seeds(customers) = ((customers / 2)...(customers / 2 + half(customers))).to_a
      def self.new_seeds(customers) = (NEW_SEEDS...(NEW_SEEDS + half(customers))).to_a

      private
        def second_system(tenant)
          erp = SourceSystems::Manager.new(@manager).create(tenant: tenant, name: NAME, key_kind: "own_id")
          seeds = SystemSteps.shared_seeds(@customers) + SystemSteps.new_seeds(@customers)
          path = PortfolioSheet.write_remote(@tmp.join("carteira-erp-#{tenant.id}.csv").to_s, seeds, today: today)
          # Pela confirmação completa, a mesma da carga que o visitante envia: é ela que reconhece o cliente pelo documento e cria a identidade remota.
          run_import(tenant, path, name: "carteira-erp-academico.csv", system: erp)
          recalc(tenant)
          system_payments(tenant, erp)
          Segment.create!(tenant: tenant, name: SEGMENT, subject: "contracts", expression: { "all" => [ { "path" => "system", "op" => "eq", "value" => erp.id } ] })
          erp
        end

        # Um em cada quatro títulos do ERP vencidos há mais de 15 dias é quitado pelo valor atualizado, achado pelo id do título no sistema (R417).
        def system_payments(tenant, erp)
          code = CHANNELS.fetch("pix").first
          bills = Bill.where(tenant_id: tenant.id, source_system_id: erp.id).joins(:customer).joins("left join bill_valuations on bill_valuations.bill_id = bills.id")
                      .where("bills.due_date < ?", today - 15).order(:id)
                      .pluck("customers.document", :external_id, Arel.sql("coalesce(bill_valuations.total_cents, bills.amount_cents)"))
          lines = [ %w[metodo_recebimento identificador documento id_titulo data_pagamento valor meio sistema] ]
          bills.each_slice(4) do |(document, external_id, cents), *|
            lines << [ code, "ERP-#{external_id}", document, external_id, (today - 1).strftime("%d/%m/%Y"), Money.format(cents), "pix", erp.name ]
          end
          path = @tmp.join("pagamentos-erp-#{tenant.id}.csv").to_s
          File.write(path, lines.map { |line| line.join(";") }.join("\n") + "\n")
          run_import(tenant, path, kind: "payments", name: "pagamentos-erp-academico.csv")
          Charges::Recalculation.new(tenant).apply(today: today)
        end
    end
  end
end
