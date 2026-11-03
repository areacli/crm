# Formulário de registro de acionamento na SPA (04 e 10; decisão 0025): o estado inteiro do formulário para os valores enviados. A tela pede de
# novo a cada mudança de canal, resultado, contrato, data ou bloco da promessa, como o htmx pedia os trechos que dependem da escolha.
json.cliente @customer.name
json.descricao "Cada tentativa de contato com #{@customer.name}. O registro não é editado nem apagado: se algo saiu errado, registre um acionamento novo com a observação."
json.valores do
  Contacts::Form::FIELDS.each { |campo| json.set! campo, @form.value(campo) }
  json.promise_bill_ids @form.promise_bill_ids
end
json.canais(ContactAttempt::CHANNELS.map { |canal| { id: canal, nome: t("contacts.channels.#{canal}") } })
json.resultados(@form.results.map { |resultado| { id: resultado.id.to_s, nome: resultado.name } })
json.contratos(@form.contracts.map { |contrato| { id: contrato.id.to_s, nome: contrato.label } })
json.contatos_sugeridos @form.suggested_contacts
json.pode_salvar_contato policy(@customer).edit_registry?
json.retorno(@form.show_return? ? { obrigatorio: @form.return_rule == "required", ajuda: "#{@form.return_rule == "required" ? "Este resultado exige a data do retorno." : "Pode ficar vazio."} Depois do contato e até 90 dias." } : nil)
names = @form.other_responsible_names
json.aviso_responsavel(names ? t("contacts.responsible_notice", count: names.size, names: names.to_sentence) : nil)
json.erro @form.error
if @form.promise_offered?
  contract = @form.promise_contract
  json.promessa do
    json.contrato_travado @form.promise_contract_locked?
    json.contrato(contract&.label)
    json.meios(Payment.payment_methods.keys.map { |meio| { id: meio, nome: t("payments.methods.#{meio}") } })
    json.prazo(@form.promise_last_day ? "Até #{date_br(@form.promise_last_day)}, o prazo máximo do item do enquadramento. Até #{@form.promise_own_days} dias depois do contato, a promessa nasce aberta; depois, aguarda aprovação." : "Escolha o contrato para ver o prazo máximo.")
    json.titulos(contract ? @form.promise_availability.entries.map { |entry|
      { id: entry.bill.id.to_s, texto: "#{entry.bill.number}, vence em #{date_br(entry.bill.due_date)}, saldo #{money(entry.bill.balance_cents)}", bloqueio: entry.blocked,
        marcado: entry.blocked.nil? && @form.promise_bill_ids.include?(entry.bill.id.to_s) }
    } : nil)
    quote = @form.promise_quote
    json.valor(quote && {
      titulo: "Valor da promessa para #{date_br(quote.promised_on)}",
      linhas: quote.rows.map { |row| { titulo: row.bill.number, **%w[principal correction fine interest fees].to_h { |c| [ c, money(row.components.fetch(c, 0)) ] }, total: money(row.total_cents) } },
      total: money(quote.total_cents)
    })
  end
else
  json.promessa nil
end
