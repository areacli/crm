# Textos da linguagem dos segmentos nas telas (13): nomes, definições e rótulos vêm do idioma, pelo catálogo.
module SegmentEditorHelper
  def segment_t(key, **options) = t("segment_language.#{key}", **options)
end
