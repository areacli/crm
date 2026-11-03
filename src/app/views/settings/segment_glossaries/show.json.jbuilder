# Glossário dos segmentos na SPA (13, R289; decisão 0025): as seções, cada termo com a definição, os detalhes e o exemplo com a leitura por extenso.
json.secoes(@glossary.map do |section|
  { titulo: section.title,
    termos: section.entries.map { |entry| { ancora: entry.anchor, termo: entry.term, definicao: entry.definition, detalhes: entry.details, exemplo: entry.example, leitura: entry.reading } } }
end)
