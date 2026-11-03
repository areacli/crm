# Ficha do cliente na SPA (R22; decisão 0025): o cabeçalho com os indicadores e as ações que a pessoa pode fazer, o cartão Contratos (filtro da
# ficha, padrões de interface, revisões 21 e 28), as contagens das abas, os títulos e a lateral. As mesmas variáveis da página do servidor.
active = @bills.select(&:active?)
overdue = active.select { |bill| bill.due_date < @today }
upcoming = active - overdue
worst = overdue.map { |bill| bill.days_overdue(@today) }.max
promises_count = @promises.size
agreements_count = @agreements&.size.to_i
tom = { success: "Success", warning: "Warning", danger: "Error", info: "Information", neutral: "None" }

json.id @customer.id
json.nome @customer.name
json.credor @customer.tenant.name
json.contrato_escolhido @contract&.id
json.indicadores do
  json.array!([
    ([ "Anonimizado", :neutral ] if @customer.anonymized?),
    ([ "Contrato #{@contract.label}", :info ] if @contract),
    (worst ? [ "Atraso de #{@brackets.label(@brackets.index_for(worst))} dias", :danger ] : [ "Sem atraso", :success ]),
    ([ pluralize(promises_count, "promessa em aberto", "promessas em aberto"), :info ] if promises_count.positive?),
    ([ pluralize(agreements_count, "proposta ou acordo", "propostas ou acordos"), :info ] if agreements_count.positive?)
  ].compact) { |(texto, tom_do_selo)| json.texto texto; json.estado tom.fetch(tom_do_selo) }
end
json.avisos do
  json.array!([
    ("Cidade não reconhecida: o endereço deste cliente não casa com a lista de municípios do IBGE, e os acordos dele usam só os feriados nacionais. Corrija o endereço no cadastro." if @city_unrecognized),
    ("Cliente anonimizado em #{date_br(@customer.anonymized_at.to_date)}. Só restam os dados que não identificam a pessoa." if @customer.anonymized?)
  ].compact)
end
json.pode do
  json.registrar_acionamento @contact_form.present?
  json.simular_acordo @can_negotiate
  json.editar_cadastro @can_edit_registry
  json.transferir_credito @can_transfer
  json.direitos_do_titular @can_handle_rights
  json.anonimizar @can_handle_rights && !@customer.anonymized?
end
json.contratos @all_contracts do |contract|
  rows = @contract_members.fetch(contract.id, [])
  own = rows.find { |row| row.customer_id == @customer.id }
  tier = @contract_tiers[contract.tier_id]
  json.id contract.id
  json.codigo contract.label
  json.titulos number_br(@contract_bill_counts.fetch(contract.id, 0))
  json.papel(own ? role_label(own, rows) : "—")
  json.clientes pluralize(rows.size, "cliente", "clientes")
  json.faixa(@contract_overdue[contract.id] ? "#{@brackets.label(@brackets.index_for(@contract_overdue[contract.id]))} dias" : "Sem atraso")
  json.enquadramento(tier ? tier.name : t("tiers.none"))
  json.enquadramento_porque(tier && (tier.catch_all? ? "Não atende a nenhum segmento do enquadramento financeiro; fica com as regras de Demais." : "Atende ao segmento: #{tier.segment.text.long_text}"))
  json.operacoes(Operations::Context.operation? ? nil : @contract_operations.fetch(contract.id, []).map { |holder| { nome: holder.name, razao_social: holder.legal_name } })
  json.credito money(@credit_totals.fetch(contract.id, 0))
end
json.abas do
  json.titulos @bills.size
  json.acionamentos @contact_history.total
  json.promessas promises_count + agreements_count
  json.pagamentos @payments.size
  json.contatos @listed_contacts.size
end
json.mostrar_contrato_nos_titulos(@all_contracts.size > 1 && !@contract)
json.titulos @bills do |bill|
  valuation = bill.active? ? @valuations[bill.id] : nil
  held = @held_bills[bill.id]
  held_agreement = (@held_by_agreement&.dig(bill.id) unless bill.renegotiated?)
  situacao =
    if bill.withdrawn? then [ "Retirado", :neutral ]
    elsif bill.renegotiated? then [ "Renegociado", :neutral ]
    elsif bill.scheduled? then [ "Aguardando efetivação", :info ]
    elsif bill.canceled? then [ "Cancelado", :neutral ]
    elsif bill.paid? then [ "Pago", :success ]
    elsif bill.due_date < @today then [ "Vencido", :danger ]
    else [ "A vencer", :info ]
    end
  json.id bill.id
  json.numero bill.number
  json.selos([ ([ "Em promessa", "Information" ] if held), ([ held_agreement.proposal? ? "Em proposta" : "Em acordo", "Information" ] if held_agreement),
               ([ "Divergência", "Warning" ] if @open_discrepancies.include?(bill.id)) ].compact.map { |texto, estado| { texto: texto, estado: estado } })
  json.contrato bill.contract.code.presence || "—"
  json.vencimento date_br(bill.due_date)
  json.valor money(bill.amount_cents)
  json.pago money(bill.paid_cents)
  json.saldo money(bill.balance_cents)
  json.atraso(bill.active? && bill.due_date < @today ? number_br(bill.days_overdue(@today)) : "—")
  json.atualizado(valuation ? money(valuation.total_cents) : "—")
  json.situacao situacao[0]
  json.situacao_estado tom.fetch(situacao[1])
  json.endereco bill_path(bill)
  json.usar_credito(@can_use_credit && Agreements::CreditOnBill.usable?(bill) && @credit_totals.fetch(bill.contract_id, 0).positive? ? money(@credit_totals[bill.contract_id]) : nil)
end
json.dados do
  json.documento @customer.formatted_document
  json.telefone(@contacts.find { |contact| contact.phone? && contact.status_valid? }&.value || "—")
  json.email(@contacts.find { |contact| contact.email? && contact.status_valid? }&.value || "—")
  json.faixa(worst ? "#{@brackets.label(@brackets.index_for(worst))} dias" : "Sem atraso")
  json.nome_mantido @customer.name_kept?
end
json.em_cobranca do
  json.vencido money(overdue.sum(&:balance_cents))
  json.a_vencer(@setting.upcoming_display == "detail_only" ? nil : money(upcoming.sum(&:balance_cents)))
  json.titulos number_br(active.size)
  json.atualizado money(overdue.sum { |bill| @valuations[bill.id]&.total_cents || bill.balance_cents })
  json.nota(
    if @value_status[:calculated_on]
      "Valor atualizado até #{date_br(@value_status[:calculated_on])} (principal corrigido, multa, juros e honorários pelas regras de #{@customer.tenant.name}).#{" Os valores estão sendo recalculados." if @value_status[:running]}"
    elsif overdue.any?
      "O valor atualizado ainda não foi calculado para este credor."
    end
  )
end
# Aba Promessas e acordos (10, R203; 11, R241): as promessas abertas e pendentes com o que a pessoa pode fazer em cada uma, as propostas e os
# acordos em andamento e o histórico dos acordos.
json.promessas @promises do |promise|
  policy = PaymentPromisePolicy.new(Current.user, promise)
  json.id promise.id
  json.numero promise.label
  json.selo promise_selo(promise)
  json.valor money(promise.total_cents)
  json.meio t("payments.methods.#{promise.payment_method}")
  json.ate date_br(promise.promised_on)
  json.pago money(promise.paid_cents)
  json.detalhe "Títulos #{promise_bill_numbers(promise)}. Feita por #{promise.customer.id == @customer.id ? "este cliente" : promise.customer.name}#{", contrato #{promise.contract.label}" if promise.contract.code.present?}."
  json.pode do
    json.aprovar policy.approve?
    json.recusar policy.approve?
    json.cancelar policy.cancel?
  end
end
json.ve_acordos !@agreements.nil?
json.acordos(@agreements || []) do |agreement|
  json.id agreement.id
  json.numero agreement.number
  json.endereco agreement_path(agreement)
  json.selos agreement_selos(agreement)
  json.valor money(agreement.value_cents)
  json.entrada money(agreement.down_payment_cents)
  json.data_da_entrada date_br(agreement.down_payment_due)
  json.parcelas(agreement.installments_count.positive? ? agreement.installments_count.to_s : "—")
  json.detalhe "Títulos #{agreement_bill_numbers(agreement)}.#{" Proposta #{t("agreements.states.#{agreement.state}").downcase}, vale até #{date_br(agreement.valid_until)}." if agreement.proposal?}"
end
json.historico_dos_acordos(@agreement_events || []) do |event|
  json.quando datetime_br(event.occurred_at)
  json.acordo event.agreement.number
  json.endereco agreement_path(event.agreement)
  json.evento "#{t("agreements.events.#{event.kind}")}#{" — #{event.data['reason']}" if event.data["reason"].present?}"
  json.quem(event.user&.name || "Sistema")
end
# Aba Pagamentos (R54, R55b; 05, R90; 11, R233): os pagos aplicados aos títulos e o crédito por contrato, com o disponível, o que aguarda
# alocação e o bloqueado, o excedente por valor reduzido e os lançamentos.
json.pagos @payments do |payment|
  json.titulo(payment.bill&.number || payment.bill_number)
  json.data date_br(payment.paid_on)
  json.valor money(payment.amount_cents)
  json.aplicado money(payment.applied_cents)
  json.estornado(payment.reversed_cents.positive? ? money(payment.reversed_cents) : "—")
  json.meio t("payments.methods.#{payment.payment_method}")
  json.metodo payment.channel.description
end
json.credito(@contracts.filter_map do |contract|
  entries = @credit_entries[contract.id].to_a
  excess = @excess_bills[contract.id].to_a
  next if entries.empty? && excess.empty?

  awaiting = @credit_awaiting.fetch(contract.id, 0)
  blocked = @credit_blocked.fetch(contract.id, 0)
  {
    id: contract.id,
    titulo: "#{contract.label}: #{money(@credit_totals.fetch(contract.id, 0) + @excess_totals.fetch(contract.id, 0))}",
    estados: (awaiting.nonzero? || blocked.nonzero?) ? [ "Disponível #{money(@credit_totals.fetch(contract.id, 0))}", ("aguardando alocação #{money(awaiting)}" if awaiting.nonzero?), ("bloqueado (estorno à espera do gestor) #{money(blocked)}" if blocked.nonzero?) ].compact.join(" · ") : nil,
    alocar: @can_allocate && awaiting.positive?,
    titulos_alocaveis: (@allocatable_bills || {}).fetch(contract.id, []).map { |bill| { id: bill.id.to_s, nome: "#{bill.number} (vence em #{date_br(bill.due_date)})" } },
    excedente: excess.map { |bill| { titulo: bill.number, endereco: bill_path(bill), valor: money(bill.amount_cents), pago: money(bill.paid_cents), excedente: money(bill.excess_cents) } },
    lancamentos: entries.map do |entry|
      origem =
        if entry.payment then "Pagamento #{entry.payment.identifier} de #{date_br(entry.payment.paid_on)}"
        elsif entry.related_contract then "#{entry.transfer_out? ? "Transferido para" : "Recebido de"} #{entry.related_contract.label}"
        else "—"
        end
      { data: datetime_br(entry.occurred_at), origem: origem, valor: money(entry.amount_cents),
        motivo: "#{t("payments.credit_reasons.#{entry.reason}")}#{" — #{entry.note}" if entry.note.present?}#{" (#{t("payments.buckets.#{entry.bucket}").downcase})" unless entry.bucket_available?}" }
    end
  }
end)
# Aba Contatos (06, R124): cada contato com a situação, a origem e o motivo; o que a pessoa com a 12 pode fazer em cada um.
json.contatos @listed_contacts do |contact|
  json.id contact.id
  json.tipo contact_kind(contact.kind)
  json.valor contact.value
  json.sem_ddd contact.no_area_code?
  json.selo selo(t("registry.statuses.#{contact.status}"), RegistryHelper::STATUS_TONES.fetch(contact.status))
  json.origem contact_origin(contact.origin)
  json.mudanca date_br(contact.updated_at.to_date)
  json.motivo(contact.reason.presence || "—")
  json.detalhe [ ("Mantido pelo credor." if contact.kept_by_tenant?), ("Veio na carga de #{date_br(contact.seen_in_import_at.to_date)}." if contact.seen_in_import_at),
                 "Última mudança em #{date_br(contact.updated_at.to_date)} por #{contact.updated_by&.name || "carga"}.", ("Pedido de não perturbe em #{date_br(contact.do_not_disturb_on)}." if contact.do_not_disturb_on),
                 ("Motivo: #{contact.reason}" if contact.reason.present?) ].compact.join(" ")
  json.endereco contact.address?
  json.pode do
    json.editar @can_edit_registry && !contact.status_invalid?
    json.invalidar @can_edit_registry && !contact.status_invalid?
    json.nao_perturbe @can_edit_registry && contact.status_valid?
    json.validar @can_edit_registry && !contact.status_valid?
  end
end
# Aba Histórico (06, R116; 13, R268): as mudanças do cadastro e as do enquadramento financeiro dos contratos.
contacts_by_id = @contacts.index_by(&:id)
json.historico_do_cadastro @registry_history do |change|
  json.quando datetime_br(change.occurred_at)
  json.mudanca registry_change_text(change, contacts_by_id)
  json.quem(change.user&.name || "sistema")
  json.origem(change.origin.present? ? contact_origin(change.origin) : "carga")
end
json.historico_do_enquadramento(@contracts.flat_map do |contract|
  @tier_history.fetch(contract.id, []).map { |entry| { contrato: contract.label, enquadramento: entry.tier&.name || t("tiers.none"), desde: date_br(entry.since) } }
end)
# Contratos de onde o crédito pode sair numa transferência (R55a): os do cliente com crédito disponível ou aguardando alocação.
if @can_transfer
  saldos = (@credit_totals.keys + @credit_awaiting.keys).uniq.index_with { |id| @credit_totals.fetch(id, 0) + @credit_awaiting.fetch(id, 0) }
  json.origens_de_transferencia(@all_contracts.select { |contract| saldos.fetch(contract.id, 0).positive? }.map { |contract| { id: contract.id.to_s, nome: "#{contract.label} (#{money(saldos[contract.id])})" } })
end
# UFs do endereço (06), para criar e corrigir contato de endereço.
json.ufs(@can_edit_registry ? Registry::Normalizer::UFS : [])
