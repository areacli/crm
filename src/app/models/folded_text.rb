# Minúsculas, sem acento e sem espaços repetidos ou nas pontas: base da comparação de nomes (R7) e da busca.
module FoldedText
  module_function

  def fold(text) = text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/\s+/, " ").strip
end
