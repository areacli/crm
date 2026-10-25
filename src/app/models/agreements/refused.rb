module Agreements
  # Configuração, simulação, proposta, aprovação, recusa, cancelamento ou aceite recusados por uma regra da especificação 11. A mensagem já vai pronta para a
  # tela. `field` diz o campo do formulário quando a recusa é de um campo (a simulação mostra a mensagem junto dele).
  class Refused < StandardError
    attr_reader :field

    def initialize(message, field: nil)
      super(message)
      @field = field
    end
  end
end
