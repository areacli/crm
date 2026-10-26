module Payments
  # Estado dos títulos enquanto a confirmação (ou a conferência) percorre o fluxo em lotes: [pago, situação, data do pagamento]. O que está no `memo` vale mais
  # que o que o fluxo e o banco dizem. Entram no memo os títulos que recebem mais de um pagamento no fluxo e os que pertencem a promessas (10): os
  # pagamentos de uma promessa alteram vários títulos, e a conferência, que não grava, precisa ver o mesmo que a confirmação. O estado do lote vai ao banco no fim dele.
  class BillStates
    # `keep_all`: guarda o estado de todo título tocado (a conferência, que não grava, precisa ver o que o arquivo já alocou); a confirmação lê o banco de cada lote.
    def initialize(shared_ids = Set.new, keep_all: false)
      @shared = shared_ids
      @keep_all = keep_all
      @memo = {}
      @lot = {}
    end

    attr_reader :lot

    def start_lot = @lot = {}

    def get(bill_id)
      @memo[bill_id] || (entry = @lot[bill_id]) && [ entry[:paid], entry[:status], entry[:paid_on] ]
    end

    def put(bill_id, paid:, status:, paid_on:, keep: false)
      @lot[bill_id] = { paid: paid, status: status, paid_on: paid_on }
      @memo[bill_id] = [ paid, status, paid_on ] if keep || @keep_all || @memo.key?(bill_id) || @shared.include?(bill_id)
    end

    def shared?(bill_id) = @shared.include?(bill_id)
  end
end
