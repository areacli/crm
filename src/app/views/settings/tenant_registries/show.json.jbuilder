# Dados do credor na SPA (06, R106, R106a; 07, prazo de guarda; decisão 0025): o cadastro de cada credor em que a pessoa tem a permissão 4, separado, e a
# última alteração.
json.ufs Registry::Normalizer::UFS
json.credores(@tenants.map do |tenant|
  last = @last_change[tenant.id]
  { id: tenant.id, nome: tenant.name,
    cadastro: { cnpj: tenant.cnpj.present? && tenant.cnpj.length == 14 ? Document.format(tenant.cnpj) : tenant.cnpj.to_s, legal_name: tenant.legal_name.to_s, trade_name: tenant.trade_name.to_s,
                street: tenant.street.to_s, number: tenant.number.to_s, complement: tenant.complement.to_s, district: tenant.district.to_s, city: tenant.city.to_s, state: tenant.state.to_s,
                zip: tenant.zip.to_s.length == 8 ? "#{tenant.zip[0, 5]}-#{tenant.zip[5, 3]}" : tenant.zip.to_s, email: tenant.email.to_s, phone: tenant.phone.to_s },
    anos_de_guarda: tenant.setting.retention_years,
    ultima: last ? "Última alteração: #{last.user&.name || "sistema"} em #{datetime_br(last.occurred_at)}." : "Cadastro ainda não preenchido." }
end)
