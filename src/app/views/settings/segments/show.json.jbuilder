# Página do segmento na SPA (13, R278; decisão 0025): o texto curto, a leitura por extenso, a situação e onde é usado.
text = @segment.text
uses = @segment.uses.to_a
json.id @segment.id.to_s
json.nome @segment.name
json.credor_id @segment.tenant_id.to_s
json.subtitulo "#{@segment.tenant.name} · #{t("segments.subjects.#{@segment.subject}")}"
json.texto text.short_text
json.leitura text.long_text
json.situacao(@segment.active? ? selo("Ativo", :success) : selo("Desativado", :neutral))
json.uso(uses.any? ? "Usado no enquadramento financeiro, item #{uses.map(&:position).join(', ')}." : "Sem uso.")
json.pode_editar policy(@segment).update?
