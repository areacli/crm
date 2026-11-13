module Ingestion
  # Um registro como o canal o entregou, ainda em texto (decisão 0031). `position` é a linha física do arquivo, que é também o cursor de retomada da
  # leitura. `values` traz o texto por campo; `extra` marca células preenchidas além do cabeçalho, e `short`, células faltando.
  RawRecord = Data.define(:position, :values, :extra, :short)
end
