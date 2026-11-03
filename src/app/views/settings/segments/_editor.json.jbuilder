# Editor do segmento na SPA (13, R285, R301 a R305; decisão 0025): o nome, o texto na linguagem, a coluna "Como fica" e onde o segmento é usado.
# Locais: segment, source, parsed, probe.
uses = segment.persisted? ? segment.uses.to_a : []
json.id segment.id&.to_s
json.credor_id segment.tenant_id.to_s
json.credor segment.tenant.name
json.nome segment.name
json.texto source
json.sujeito_fixo segment.persisted?
json.usado uses.any?
json.usos(uses.map { |tier| "Enquadramento financeiro, item #{tier.position}" })
json.como_fica { json.partial! "settings/segments/como_fica", segment: segment, source: source, parsed: parsed, probe: probe }
json.conferir { json.partial! "settings/segments/probe", probe: probe, subject: (parsed&.subject || segment.subject || "contracts"), expression: (parsed&.ok? ? Segments::Expression.new(parsed.tree) : nil) }
