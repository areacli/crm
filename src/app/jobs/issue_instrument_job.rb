# Emite um boleto ou Pix (12, R272): fila `default`. O serviço decide o que repetir (só erro de rede que não duplica); este job só reenfileira.
class IssueInstrumentJob < ApplicationJob
  queue_as :default

  # Uma tentativa a mais que o limite do serviço: o serviço marca `failed` na última, antes de o job desistir.
  retry_on Payments::Providers::NetworkError, wait: :polynomially_longer, attempts: Payments::Issuer::MAX_ATTEMPTS + 1

  def perform(instrument_id)
    instrument = PaymentInstrument.find_by(id: instrument_id) or return
    Payments::Issuer.new.perform(instrument)
  end
end
