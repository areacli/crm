module Payments
  module Providers
    # Falha de rede ou indisponibilidade temporária do fornecedor (R272: a única que se tenta de novo). `retry_safe`: a repetição não pode duplicar
    # nada (a conexão nem chegou a ser feita, o fornecedor disse que não processou, ou a operação é idempotente, como o Pix pelo `txid` nosso).
    # Falso quando o pedido pode ter sido processado sem que a resposta chegasse (por exemplo, o tempo esgotou ao ler a resposta de um boleto).
    class NetworkError < Error
      attr_reader :retry_safe

      def initialize(message = nil, retry_safe: false)
        super(message)
        @retry_safe = retry_safe
      end
    end
  end
end
