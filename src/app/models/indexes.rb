# Índices do Banco Central (08, R142 a R147). O cliente HTTP é trocável: os testes injetam um falso, e nada chama a internet fora da busca real.
module Indexes
  class SourceError < StandardError; end

  class << self
    attr_writer :client

    # Na demonstração (CRM_DEMO=1) nunca se chama o Banco Central: o cliente é o fictício.
    def client = @client || (Demo.enabled? ? Demo::IndexClient.new : BcbClient.new)
  end
end
