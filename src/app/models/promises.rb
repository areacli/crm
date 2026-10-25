# Promessas de pagamento (especificação 10): preço na data prometida, registro com alçada, aprovação, cancelamento, avaliação pelos pagamentos e
# pela tarefa diária. As regras ficam em serviços de Ruby; a tela só pergunta e mostra.
module Promises
  NUMBER_FORMAT = /\APRM-\d{6,}\z/

  # Número da promessa (R187a): PRM- e seis dígitos, único dentro do credor, dado quando ela fica aberta. Formato que não se confunde com número
  # de título: a carga de carteira recusa título com esse formato.
  def self.format_number(sequence) = format("PRM-%06d", sequence)

  def self.number?(text) = NUMBER_FORMAT.match?(text.to_s)
end
