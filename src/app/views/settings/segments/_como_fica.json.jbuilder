# Coluna "Como fica" na SPA (13, R278, R302; decisão 0025): para cada linha escrita, a leitura por extenso ou os erros, com o número da linha, e o
# segmento inteiro por extenso. Serve ao rascunho (o `draft` renderiza este trecho sozinho) e às páginas de novo e de editar (dentro de `como_fica`).
# Locais: segment, source, parsed, probe (o resultado do "Conferir" fica por conta da tela, pelo trecho `_probe`).
errors = parsed ? parsed.errors.group_by(&:first).transform_values { |list| list.map(&:last) } : {}
text = parsed&.ok? ? Segments::Text.new(Segments::Expression.new(parsed.tree)) : nil
subject = parsed&.subject || segment.subject || "contracts"

json.escrito !parsed.nil?
json.valido parsed&.ok? || false
json.sujeito subject
lines = source.to_s.split(/\r?\n/).each_with_index.filter_map do |line, index|
  number = index + 1
  next if parsed.nil? || line.strip.empty?

  node = parsed.nodes[number]
  leitura = if errors[number] then nil
  elsif number == 1 then "Seleciona #{segment_t("subjects.#{subject}.long")}."
  elsif node == :group then "Pelo menos uma das linhas de baixo."
  elsif node then "#{Segments::Text.new(Segments::Expression.new("grammar" => 1, "subject" => subject, "all" => [ node ])).long(node).upcase_first}."
  end
  { numero: number, texto: line.strip, leitura: leitura, erros: errors[number] || [] }
end
json.linhas lines
json.leitura(text && (text.long_text.presence || "Escreva pelo menos uma condição."))
json.erros(text ? nil : (errors.size == 1 ? "1 linha com erro." : "#{errors.size} linhas com erro.")) if parsed
