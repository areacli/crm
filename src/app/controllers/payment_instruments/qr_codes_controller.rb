module PaymentInstruments
  # A imagem do QR Code do Pix guardada aqui (12, R275). Mesmas garantias do PDF.
  class QrCodesController < ApplicationController
    def show
      instrument = PaymentInstrument.find(params[:payment_instrument_id])
      authorize instrument, :qr_code?
      bytes = instrument.pix? ? Payments::InstrumentReader.new(instrument).qr_png : nil
      return head(:not_found) unless bytes

      response.headers["Cache-Control"] = "private, no-store"
      send_data bytes, type: "image/png", disposition: "inline", filename: "pix-#{instrument.id}.png"
    rescue Payments::InstrumentReader::NotDeliverable
      head :not_found
    end
  end
end
