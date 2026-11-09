# Mapa de módulos do navegador (importmap), sem empacotador e sem Node. htmx fica na árvore (vendor/javascript), não numa CDN; desde a fase 8 do port ele serve só
# à página pública de pagamento, com o `cable` dela.
pin "cable", preload: "checkout"
pin "htmx.org", to: "htmx.org.js", preload: "checkout" # @2.0.11 (a versão 4.0 ainda é a marcação `next` do npm)
pin "@rails/actioncable", to: "actioncable.esm.js", preload: "checkout"

# Página pública de pagamento (12, parte C): o módulo da página, o módulo de cada adaptador de cartão (`driver` do manifesto) e a biblioteca do fornecedor
# (`script` do manifesto), tudo na árvore e com SHA-256 conferido por teste. Carregados só nessa página (preload: false), nunca de uma CDN.
pin "checkout", preload: "checkout"

# SPA em EasyUI (decisão 0028): os módulos da casca. jQuery e EasyUI são globais, carregados por `spa/inicio` só quando a tela serve.
pin_all_from "app/javascript/spa", under: "spa", preload: false
pin "payments/drivers/fake", to: "payments/drivers/fake.js", preload: false
pin "payments/drivers/efi", to: "payments/drivers/efi.js", preload: false
pin "payment-token-efi", to: "payment-token-efi.js", preload: false # payment-token-efi@3.4.1 (MIT), publicada em 09/07/2026, do npm
