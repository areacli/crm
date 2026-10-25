# Mapa de módulos do navegador (importmap), sem empacotador e sem Node. htmx fica na árvore (vendor/javascript), não numa CDN.
pin "application"
pin "cable"
pin "htmx.org", to: "htmx.org.js" # @2.0.11 (a versão 4.0 ainda é a marcação `next` do npm)
pin "@rails/actioncable", to: "actioncable.esm.js"
