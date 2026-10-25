module Demo
  class Dataset
    # Instrumentos de pagamento do fornecedor falso (12): boletos e Pix emitidos (PDF e QR Code guardados daqui), uma emissão que falhou, um boleto cancelado e o
    # link de pagamento de exemplo, num endereço fixo (`/pagar/demonstracao-pagamento`) para o blog e para a V5. Nenhuma chamada a fornecedor real.
    module InstrumentSteps
      CHECKOUT_TOKEN = "demonstracao-pagamento".freeze

      private
        def instruments(tenant)
          issuer = Payments::Issuer.new
          # O falso devolve um PNG de 1 pixel: sem imagem do fornecedor, o QR Code do Pix é gerado daqui (rqrcode) a partir do copia e cola, e a página mostra um de verdade.
          Payments::Providers::Fake.omit_qr_image!
          sources = candidates(tenant, 8, older_than: 5)
          emit = lambda do |source, kind|
            bill = source[:bills].first
            instrument = issuer.request(tenant: tenant, kind: kind, amount_cents: bill.amount_cents, customer: source[:customer], due_on: today + 5, reference: [ "bill", bill.number ])
            issuer.perform(instrument)
            instrument.reload
          end

          sources.first(4).each { |source| emit.call(source, "boleto") }
          sources[4, 3].each { |source| emit.call(source, "pix") }
          Payments::Providers::Fake.fail_on(:issue_pix, Payments::Providers::Error.new("Fornecedor indisponível (falha simulada)"), times: 1)
          emit.call(sources[7], "pix")

          # Link de exemplo: boleto, Pix e cartão para o mesmo valor.
          example = candidates(tenant, 1, older_than: 5).first
          bill = example[:bills].first
          boleto = emit.call(example, "boleto")
          pix = emit.call(example, "pix")
          checkout = Payments::Checkouts.create(tenant: tenant, customer: example[:customer], instruments: [ boleto, pix ], card: true, amount_cents: bill.amount_cents,
                                                description: "#{bill.description} (#{bill.number})")
          checkout.update_column(:token, CHECKOUT_TOKEN)
          Payments::Providers::Fake.reset!
        end
    end
  end
end
