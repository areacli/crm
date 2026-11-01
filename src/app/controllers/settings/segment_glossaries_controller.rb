module Settings
  # Glossário dos segmentos (13, R289): cada atributo, coleção, qualificador, agregação e quantificador com o nome, a definição, o campo principal
  # do atalho e um exemplo com a leitura por extenso. Gerado do catálogo, para nunca divergir dele. Vê quem vê os segmentos.
  class SegmentGlossariesController < ApplicationController
    def show
      authorize Segment, :index?
      @glossary = ::Segments::Glossary.entries
    end
  end
end
