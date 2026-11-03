# Linha do tempo da ficha na SPA (padrões de interface, revisão 24): os eventos do mais recente ao mais antigo, 10 por página, com o filtro
# por tipo. Os mesmos textos do cartão das páginas do servidor.
json.tipo @timeline.kind
json.tipos @timeline.kinds
json.pagina @timeline.page
json.paginas @timeline.pages
json.vazio(@timeline.kind == "distribuicao" ? "Nenhuma distribuição: a equipe do credor cobra este cliente." : "Nenhum evento para este cliente.")
json.eventos @timeline.events do |event|
  record = event.record
  origin = @timeline.origins[record.try(:operation_id)] unless event.source == :distribution
  json.marcador(event.source == :distribution ? (record.entry? ? "entrada" : "saida") : "atendimento")
  case event.source
  when :contact_attempt
    json.quando datetime_br(event.at)
    json.titulo "Acionamento"
    json.complemento t("contacts.channels.#{record.channel}")
    json.detalhe [ record.result.name, (record.contract && "Contrato #{record.contract.label}"), (record.summary_only_for_viewer? ? "Outra origem" : record.user&.name) ].compact.join(" · ")
    json.promessa(record.promise && "Promessa #{record.promise.label}, #{money(record.promise.total_cents)} até #{date_br(record.promise.promised_on)}")
    json.selos(record.promise ? [ promise_selo(record.promise) ] : [])
  when :agreement
    json.quando datetime_br(event.at)
    json.titulo "Proposta de acordo"
    json.complemento record.label
    json.endereco(policy(record).show? ? agreement_path(record) : nil)
    json.detalhe [ money(record.total_cents), record.user&.name ].compact.join(" · ")
    json.selos agreement_selos(record)
  else
    json.quando(event.with_time ? datetime_br(event.at) : date_br(record.date))
    json.titulo(record.entry? ? "Entrada" : "Saída")
    json.complemento record.operation.short_name
    json.detalhe record.detail
    json.selos []
  end
  json.origem(origin && { nome: origin.short_name, razao_social: origin.legal_name })
end
