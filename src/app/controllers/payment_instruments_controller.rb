# Dados de um instrumento emitido, em JSON, para quem monta a mensagem (12, R275): estado, valor, vencimento e as linhas em texto. Sem tela:
# a emissão e a consulta ficam fora do back office. Permissão do credor do instrumento (404 registrado, V10).
class PaymentInstrumentsController < ApplicationController
  def show
    instrument = PaymentInstrument.find(params[:id])
    authorize instrument
    reader = Payments::InstrumentReader.new(instrument)
    return head(:not_found) unless reader.deliverable?

    response.headers["Cache-Control"] = "private, no-store"
    delivery = reader.delivery
    render json: { id: delivery.id, kind: delivery.kind, state: delivery.state, amount_cents: delivery.amount_cents, due_on: delivery.due_on.iso8601,
                   digitable_line: delivery.digitable_line, copy_paste: delivery.copy_paste, has_pdf: instrument.boleto_pdf.attached?, has_qr_code: instrument.pix_qr_png.attached? }
  end
end
