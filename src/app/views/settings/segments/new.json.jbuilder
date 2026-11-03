# Segmento novo na SPA (13, R290, R304; decisão 0025): o editor em branco, de um exemplo ou da cópia de outro, e os exemplos quando começa em branco.
json.partial! "settings/segments/editor", segment: @segment, source: @source, parsed: @parsed, probe: @probe
json.exemplos(params[:exemplo].blank? && params[:from].blank? && @parsed.nil? ? Segments::Examples::LIST.map { |example| { id: example.key, nome: example.name } } : [])
