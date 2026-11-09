module PaymentInstruments
  # A imagem do QR Code do Pix guardada aqui (12, R275). Mesmas garantias do PDF.
  class QrCodesController < ApplicationController
    # Serve página ou arquivo direto, fora da casca (impressão, download, entrada).
    skip_before_action :redirect_page_to_shell
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
