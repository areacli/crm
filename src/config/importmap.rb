# Mapa de módulos do navegador (importmap), sem empacotador e sem Node. htmx fica na árvore (vendor/javascript), não numa CDN.
pin "application", preload: "application"
pin "cable", preload: %w[application checkout]
pin "htmx.org", to: "htmx.org.js", preload: %w[application checkout] # @2.0.11 (a versão 4.0 ainda é a marcação `next` do npm)
pin "@rails/actioncable", to: "actioncable.esm.js", preload: %w[application checkout]

# Página pública de pagamento (12, parte C): o módulo da página, o módulo de cada adaptador de cartão (`driver` do manifesto) e a biblioteca do fornecedor
# (`script` do manifesto), tudo na árvore e com SHA-256 conferido por teste. Carregados só nessa página (preload: false), nunca de uma CDN.
pin "checkout", preload: "checkout"
pin "payments/drivers/fake", to: "payments/drivers/fake.js", preload: false
pin "payments/drivers/efi", to: "payments/drivers/efi.js", preload: false
pin "payment-token-efi", to: "payment-token-efi.js", preload: false # payment-token-efi@3.4.1 (MIT), publicada em 09/07/2026, do npm
