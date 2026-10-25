# Minúsculas, sem acento e sem espaços repetidos ou nas pontas: base da comparação de nomes (R7) e da busca.
module FoldedText
  module_function

  # Texto só ASCII não tem acento: pula a normalização Unicode (medido na V4 de cadastros: é o custo dominante do nome e do logradouro).
  def fold(text)
    text = text.to_s
    text = text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "") unless text.ascii_only?
    text.downcase.gsub(/\s+/, " ").strip
  end
end
