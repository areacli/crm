# Lista de importações na SPA (R10, R56; decisão 0025): o que a pessoa pode importar e as importações da página, com as ações de cada uma.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.pode_importar(Import.kinds.keys.select { |kind| policy(Import.new(kind: kind)).new? })
json.linhas @imports do |import|
  json.id import.id
  json.recebida datetime_br(import.created_at)
  json.credor import.tenant.name
  json.tipo t("imports.kinds.#{import.kind}")
  json.arquivo import.original_name
  json.modo(import.portfolio? ? t("imports.modes.#{import.mode}") : "—")
  json.enviada_por(import.user&.name || "—")
  json.partial! "imports/selo", import: import
  json.pode_confirmar policy(import).confirm?
  json.mensagem_de_confirmar(t("imports.confirm_message.#{import.kind}") + (import.portfolio? && import.full_sync? ? " Os que não vieram no arquivo saem da cobrança." : ""))
  json.mensagem_de_descartar t("imports.discard_message.#{import.kind}")
end
