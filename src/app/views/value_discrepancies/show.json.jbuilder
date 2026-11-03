# Divergência de um título na SPA (05, R99, R100; decisão 0025): o que mudou, o tratamento e as escolhas do tratamento.
item = @discrepancy
json.id item.id
json.titulo item.bill.number
json.credor item.tenant.name
json.selo(item.open? ? selo("Aberta", :warning) : selo("Tratada", :success))
json.cliente item.bill.customer.name
json.cliente_id(@can_view_customer ? item.bill.customer_id : nil)
json.titulo_endereco(@can_view_customer ? bill_path(item.bill) : nil)
json.pode_tratar item.open? && policy(item).create?
pares = [ [ "Título", item.bill.number ], [ "Valor anterior", money(item.previous_cents) ], [ "Valor informado", money(item.reported_cents) ], [ "Pago até então", money(item.allocated_cents) ],
          [ "Saldo antes", money(item.balance_before_cents) ], [ "Saldo depois", money(item.balance_after_cents) ] ]
pares << [ "Excedente", money(item.excess_cents) ] if item.excess_cents.positive?
pares << [ "Efeito aplicado", "#{t("discrepancies.effects.#{item.effect}")} (política: #{t("discrepancies.policies.#{item.policy}").downcase})" ]
pares << [ "Registrada em", datetime_br(item.created_at) ]
json.o_que_mudou(pares.map { |rotulo, valor| { rotulo: rotulo, valor: valor } })
json.nota_do_efeito(item.effect_record_only? ? "Título pago: a carga nunca o altera. A divergência existe só para registro." : nil)
json.tratamento(item.handled? ? [ [ "Tratada por", item.handled_by&.name || "—" ], [ "Em", datetime_br(item.handled_at) ], [ "Escolha", t("discrepancies.choices.#{item.choice}") ], [ "Nota", item.note ] ].map { |rotulo, valor| { rotulo: rotulo, valor: valor } } : [])
escolhas = [ { id: "keep", nome: t("discrepancies.choice_help.keep") } ]
escolhas << { id: "apply", nome: t("discrepancies.choice_help.apply", amount: money(item.reported_cents)) } if item.applicable? && !item.stale?
json.escolhas escolhas
json.aviso_do_valor(item.applicable? && item.stale? ? t("discrepancies.value_changed") : nil)
