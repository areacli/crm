# Política de segurança de conteúdo (CSP). O CRM não tem política global ainda: a única página que a define é a de pagamento do cliente
# (`CheckoutBaseController`, 12 parte C, R278), porque é a única que roda JavaScript de um fornecedor. Aqui fica só o gerador do nonce: valor aleatório
# a cada pedido (não a sessão, que a página pública nem tem), aplicado ao `script-src`. As tags do importmap e do módulo de entrada levam o nonce sozinhas.
# Guia: https://guides.rubyonrails.org/security.html#content-security-policy
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
