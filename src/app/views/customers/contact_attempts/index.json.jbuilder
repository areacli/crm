# Aba Acionamentos da ficha na SPA (R74; decisão 0025): o histórico do mais recente ao mais antigo, 20 por página, no contrato escolhido.
# O detalhe de cada linha (P26) vai junto, para o painel abaixo da tabela.
json.total @history.total
json.pagina @history.page
json.paginas @history.pages
json.linhas @history.records do |attempt|
  promise = attempt.promise
  text = attempt.text.presence unless attempt.summary_only_for_viewer?
  json.id attempt.id
  json.quando datetime_br(attempt.contacted_at)
  json.canal t("contacts.channels.#{attempt.channel}")
  json.resultado attempt.result.name
  json.com_promessa promise.present?
  json.retorno(attempt.return_at ? datetime_br(attempt.return_at) : "—")
  json.registrado_por(attempt.summary_only_for_viewer? ? "Outra origem" : (attempt.user&.name || "—"))
  json.texto(text || "—")
  json.detalhe [ ("Contrato #{attempt.contract.label}" if attempt.contract), attempt.contact_used.presence, t("contacts.kinds.#{attempt.result_kind}"), "lançado em #{datetime_br(attempt.created_at)}" ].compact.join(" · ")
  json.promessa(promise && {
    texto: "Promessa #{promise.label}, #{money(promise.total_cents)} por #{t("payments.methods.#{promise.payment_method}")} até #{date_br(promise.promised_on)}#{" — #{promise.reason}" if promise.reason.present?}",
    selo: promise_selo(promise)
  })
end
