module Payments
  # Leitura do instrumento guardado, para quem entrega (12, R275): o futuro disparador da mensageria e os controladores autenticados. Devolve só o
  # que se entrega ao cliente: a linha digitável e o "copia e cola" em texto, e os bytes do PDF e da imagem do QR Code guardados aqui, conferidos
  # pelo SHA-256. Nunca devolve o endereço do fornecedor (não se guarda).
  class InstrumentReader
    class NotDeliverable < StandardError; end

    Delivery = Data.define(:id, :kind, :state, :amount_cents, :due_on, :digitable_line, :copy_paste, :pdf_sha256, :qr_sha256)

    # Estados cujos dados e arquivos ainda servem a quem paga ou confere.
    DELIVERABLE_STATES = %w[active paid expired].freeze

    def initialize(instrument) = @instrument = instrument

    def deliverable? = @instrument.state.in?(DELIVERABLE_STATES)

    def delivery
      raise NotDeliverable unless deliverable?

      Delivery.new(id: @instrument.id, kind: @instrument.kind, state: @instrument.state, amount_cents: @instrument.amount_cents, due_on: @instrument.due_on,
                   digitable_line: @instrument.digitable_line, copy_paste: @instrument.copy_paste, pdf_sha256: @instrument.boleto_pdf_sha256, qr_sha256: @instrument.pix_qr_sha256)
    end

    # Texto para colocar na mensagem: a linha digitável do boleto ou o "copia e cola" do Pix.
    def text = @instrument.boleto? ? delivery.digitable_line : delivery.copy_paste

    def pdf = file(:boleto_pdf, @instrument.boleto_pdf_sha256)

    def qr_png = file(:pix_qr_png, @instrument.pix_qr_sha256)

    private
      def file(attachment, sha256)
        raise NotDeliverable unless deliverable? && @instrument.public_send(attachment).attached?

        bytes = @instrument.public_send(attachment).download
        raise NotDeliverable unless Digest::SHA256.hexdigest(bytes) == sha256

        bytes
      end
  end
end
