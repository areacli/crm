module Agreements
  # Calendário bancário de uma praça (11, R249, DA36): o nacional, calculado (`Charges::BusinessDays`), mais os feriados estaduais e municipais importados.
  # Todo vencimento e todo fim de prazo de título de acordo que cair em dia não útil passa ao dia útil seguinte. A praça é congelada no acordo, e
  # mudar a tabela de feriados não muda vencimento já gerado.
  class Calendar
    # `extra`: datas de feriado local (estadual e municipal) da praça.
    def initialize(extra = Set.new)
      @extra = extra.to_set
    end

    # Só os dias nacionais: o devedor sem endereço ou com cidade que não casou com o IBGE (R249).
    def self.national = new

    # O calendário da praça (município do IBGE), com os feriados do estado e do município dele nos anos próximos; sem praça, o nacional.
    def self.for(municipality, years: nil)
      return national unless municipality

      scope = Holiday.for_square(municipality)
      scope = scope.where(date: Date.new(years.min, 1, 1)..Date.new(years.max, 12, 31)) if years
      new(scope.pluck(:date))
    end

    def business?(date) = Charges::BusinessDays.business?(date) && !@extra.include?(date)

    # O próprio dia, se útil; senão, o dia útil seguinte.
    def next_business(date)
      date += 1 until business?(date)
      date
    end

    # O dia útil `count` dias úteis depois de `date` (a entrada é "do dia útil seguinte ao prazo da entrada", R213).
    def add_business_days(date, count)
      count.times { date = next_business(date + 1) }
      date
    end

    def extra_dates = @extra.sort
  end
end
