module Charges
  # Valor atualizado de um título (R169), em centavos inteiros. `stretches` e `notes` só vêm com a memória de cálculo (R174).
  class Result
    attr_accessor :principal, :corrected_principal, :fine, :interest, :fees, :total
    attr_writer :stretches, :notes

    def initialize(principal: 0, corrected_principal: 0, fine: 0, interest: 0, fees: 0, total: 0)
      @principal = principal
      @corrected_principal = corrected_principal
      @fine = fine
      @interest = interest
      @fees = fees
      @total = total
    end

    def stretches = @stretches ||= []
    def notes = @notes ||= []

    # Correção acumulada: o que o principal corrigido tem a mais que o principal (componente "correção" da alocação).
    def correction = [ corrected_principal - principal, 0 ].max

    def components = { "interest" => interest, "fine" => fine, "fees" => fees, "correction" => correction, "principal" => principal }

    def recompute_total! = (self.total = corrected_principal + fine + interest + fees; self)

    # R197a, R226: tira os encargos já alocados, componente a componente, nunca abaixo de zero.
    def minus_paid(paid)
      return self if paid.blank?

      self.corrected_principal = principal + [ corrected_principal - principal - paid.fetch("correction", 0), 0 ].max
      self.fine = [ fine - paid.fetch("fine", 0), 0 ].max
      self.interest = [ interest - paid.fetch("interest", 0), 0 ].max
      self.fees = [ fees - paid.fetch("fees", 0), 0 ].max
      recompute_total!
    end
  end
end
