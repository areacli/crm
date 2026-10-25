module Payments
  # Imagem do QR Code do Pix gerada aqui, a partir do "copia e cola", quando o fornecedor não devolve a dele em PNG (12, R273, premissa IP-P3).
  # Usa a gem `rqrcode` (Ruby puro). O conteúdo do QR Code é exatamente o texto do "copia e cola"; correção de erro média (M).
  module QrCode
    module_function

    def png(text)
      raise ArgumentError, "texto do QR Code vazio" if text.to_s.strip.empty?

      RQRCode::QRCode.new(text.to_s, level: :m).as_png(size: 480, border_modules: 4).to_s
    end
  end
end
