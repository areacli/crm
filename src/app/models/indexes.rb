# Índices do Banco Central (08, R142 a R147). O cliente HTTP é trocável: os testes injetam um falso, e nada chama a internet fora da busca real.
module Indexes
  class SourceError < StandardError; end

  class << self
    attr_writer :client

    def client = @client || BcbClient.new
  end
end
