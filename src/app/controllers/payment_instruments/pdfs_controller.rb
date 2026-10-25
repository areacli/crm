module PaymentInstruments
  # O PDF do boleto guardado aqui (12, R275). Nunca redireciona ao fornecedor nem a um endereço assinado do Active Storage: os bytes saem daqui,
  # depois de conferidos pelo SHA-256, para quem tem a permissão no credor do instrumento.
  class PdfsController < ApplicationController
    def show
      instrument = PaymentInstrument.find(params[:payment_instrument_id])
      authorize instrument, :pdf?
      bytes = instrument.boleto? ? Payments::InstrumentReader.new(instrument).pdf : nil
      return head(:not_found) unless bytes

      response.headers["Cache-Control"] = "private, no-store"
      send_data bytes, type: "application/pdf", disposition: "inline", filename: "boleto-#{instrument.id}.pdf"
    rescue Payments::InstrumentReader::NotDeliverable
      head :not_found
    end
  end
end
