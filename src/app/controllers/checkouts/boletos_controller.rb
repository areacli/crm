module Checkouts
  # O PDF do boleto guardado aqui, pelo token do link (R279): nunca o endereço do fornecedor, nunca redirecionamento.
  class BoletosController < CheckoutBaseController
    def show
      instrument = checkout.offers?("boleto") ? checkout.deliverable_instrument("boleto") : nil
      bytes = instrument && Payments::InstrumentReader.new(instrument).pdf
      return render_unavailable unless bytes

      send_data bytes, type: "application/pdf", disposition: "inline", filename: "boleto.pdf"
    rescue Payments::InstrumentReader::NotDeliverable
      render_unavailable
    end
  end
end
