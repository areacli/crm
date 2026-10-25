module Checkouts
  # A imagem do QR Code do Pix guardada aqui, pelo token do link (R279).
  class QrCodesController < CheckoutBaseController
    def show
      instrument = checkout.offers?("pix") ? checkout.deliverable_instrument("pix") : nil
      bytes = instrument && Payments::InstrumentReader.new(instrument).qr_png
      return render_unavailable unless bytes

      send_data bytes, type: "image/png", disposition: "inline", filename: "pix.png"
    rescue Payments::InstrumentReader::NotDeliverable
      render_unavailable
    end
  end
end
