module Demo
  class Dataset
    # Operações (14) na Escola Alfa: a Recupera, com o usuário público de operação como gestor, recebe pela regra os contratos de cartão de crédito
    # (vencidas) e à mão alguns clientes (vencidas e a vencer); a Cobra Digital recebe outros clientes à mão. Acionamentos com a origem de cada uma.
    module OperationSteps
      RECUPERA = [ "11222333000262", "Recupera Cobranças Ltda", "Recupera" ].freeze
      COBRA = [ "55777888000165", "Cobra Digital Serviços Ltda", "Cobra Digital" ].freeze

      private
        def operations(tenant)
          profile = tenant.profiles.create!(name: "Operador de operação", available_to_operations: true,
                                            permissions: Permission::OPERATOR)
          accreditor = Operations::Accreditor.new(@manager)
          recupera = accredit(accreditor, tenant, RECUPERA, Demo.email("operacao"))
          cobra = accredit(accreditor, tenant, COBRA, "gestor@cobradigital.exemplo.com.br")
          [ recupera, cobra ].each { |accreditation| accreditor.link(accreditation, user: accreditation.operation.members.first.user, profile: profile) }
          @operation_user = recupera.operation.members.first.user

          # A regra (R342): contratos de cartão de crédito, só as vencidas, à Recupera.
          segment = Segment.find_by!(tenant: tenant, name: "Cartão de crédito")
          DistributionRuleItem.create!(tenant: tenant, segment: segment, operation_ids: [ recupera.operation_id ], exposure: "overdue", position: 1)
          tenant.setting.update!(distribution_rules_version: tenant.setting.distribution_rules_version + 1)
          DistributionRules::Recalculation.new(tenant).apply(today: today)

          # À mão: clientes com atraso, metade para cada operação, por 60 dias.
          distributor = Distributions::Distributor.new(@manager)
          ruled = Distribution.where(tenant: tenant, ended_at: nil).select(:contract_id)
          customers = Customer.where(tenant_id: tenant.id, id: Bill.overdue(today).where(tenant_id: tenant.id).select(:customer_id))
                              .where.not(id: ContractCustomer.where(contract_id: ruled).select(:customer_id)).order(:id).limit(400).to_a
          customers.each_with_index do |customer, index|
            operation = index.even? ? recupera.operation : cobra.operation
            distributor.distribute(tenant: tenant, operation: operation, customer: customer, exposure: index % 4 < 2 ? "all" : "overdue",
                                   starts_on: today - 20, ends_on: today + 40)
          rescue Distributions::Refused
            # O cliente que divide contrato com outro já distribuído fica de fora (exclusividade, R312).
            next
          end
          Operations::ReachBuilder.new(tenant).rebuild(on: today)
          operation_attempts(tenant, recupera.operation)
        end

        def accredit(accreditor, tenant, (cnpj, legal_name, short_name), email)
          accreditation, user, = accreditor.accredit(tenant: tenant, cnpj: cnpj, legal_name: legal_name, short_name: short_name, manager_name: "Gestor da #{short_name}",
                                                     manager_email: email)
          # O usuário público de operação: senha fixa e legível, como os outros (sobrevive à recriação, sem vínculo até aqui).
          public_user("operacao", "Operação da demonstração") if user && email == Demo.email("operacao")
          accreditation
        end

        # Acionamentos da Recupera nos clientes que estão com ela, com a origem (R315).
        def operation_attempts(tenant, operation)
          results = ContactResult.where(tenant_id: tenant.id).order(:position).to_a
          customer_ids = Distribution.where(tenant: tenant, operation: operation, ended_at: nil).where.not(customer_id: nil).pluck(:customer_id)
          now = Time.current
          rows = customer_ids.each_with_index.map do |customer_id, i|
            result = results[i % results.size]
            when_at = now - (i % 15).days - (i * 13 % 300).minutes
            { tenant_id: tenant.id, customer_id: customer_id, user_id: @operation_user.id, operation_id: operation.id, result_id: result.id, result_kind: result.kind,
              channel: %w[phone whatsapp sms][i % 3], contact_used: People.phone(i), text: (i % 3).zero? ? "Texto fictício da Recupera." : nil, contacted_at: when_at,
              return_at: (when_at + 3.days if result.return_required?), created_at: when_at, updated_at: when_at }
          end
          ContactAttempt.insert_all!(rows) if rows.any?
        end
    end
  end
end
