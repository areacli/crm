# Acordos por novação (especificação 11): simulação, proposta com alçada, termo, aceite e, nas etapas seguintes, efetivação, pagamentos, quebra,
# estornos e reversão. As regras ficam em serviços de Ruby (`app/models/agreements/`); a tela só pergunta e mostra. Dinheiro sempre em centavos inteiros.
module Agreements
  # Número do acordo (R210): ACD- e seis dígitos, único dentro do credor, dado quando a proposta é gravada. Os títulos de acordo levam o sufixo
  # (`ACD-000123-00` para a entrada, `-01`, `-02`... para as parcelas, `-Q` para o título da quebra) e existem desde o aceite.
  NUMBER_FORMAT = /\AACD-\d{6,}(-(\d{2}|Q|E\d+))?\z/

  # Os componentes de um título, na ordem em que um pagamento os cobre no título de acordo depois dos encargos de atraso e dos juros do parcelamento (R224, R227): os cinco do valor
  # atualizado (09, R169) e, no acordo sobre acordo, os juros do parcelamento e os encargos de atraso herdados do título de acordo anterior (R250), depois dos juros e antes da multa.
  BASE_ORDER = %w[interest inherited_installment_interest inherited_late fine fees correction principal].freeze
  INHERITED = %w[inherited_installment_interest inherited_late].freeze

  def self.format_number(sequence) = format("ACD-%06d", sequence)

  def self.number?(text) = NUMBER_FORMAT.match?(text.to_s)
end
