module Payments
  module Providers
    # Falha do fornecedor (recusa, indisponibilidade). A mensagem é segura para mostrar e gravar.
    class Error < StandardError; end
  end
end
