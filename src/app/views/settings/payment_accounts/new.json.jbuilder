# Nova integração na SPA (12, R259): a escolha (credor, meio e fornecedor) e, com ela feita, os campos do manifesto e os métodos de recebimento ativos.
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.meios(Payments::Providers::MODALITIES.map { |modality| { id: modality, nome: t("payments.accounts.modalities.#{modality}") } })
json.fornecedores(Payments::Providers.names.map { |name| { id: name, nome: provider_name(name) } })
json.escolha({ credor: (@account.tenant_id || @tenants.first&.id).to_s, meio: @account.modality.to_s, fornecedor: @account.provider.to_s })
json.escolhida @chosen
json.ambientes(PaymentAccount.environments.keys.map { |environment| { id: environment, nome: t("payments.accounts.environments.#{environment}") } })
json.metodos(@channels.map { |channel| { id: channel.id.to_s, nome: "#{channel.code} · #{channel.description}" } })
json.titulo_dos_dados("Dados da integração: #{t("payments.accounts.modalities.#{@account.modality}")} em #{provider_name(@account.provider)}") if @chosen
json.partial!("settings/payment_accounts/campos", account: @account) if @chosen
