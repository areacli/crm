module Charges
  # Dia útil nacional (09, R164, M7): dia com expediente bancário. Não é sábado, domingo, feriado nacional nem dia nacional sem expediente
  # (segunda e terça de Carnaval, Corpus Christi, 31/12). Só o calendário nacional: o título comum não tem praça (feriados locais são da 11).
  module BusinessDays
    FIXED = [ [ 1, 1 ], [ 4, 21 ], [ 5, 1 ], [ 9, 7 ], [ 10, 12 ], [ 11, 2 ], [ 11, 15 ], [ 11, 20 ], [ 12, 25 ] ].freeze # 20/11: Lei 14.759/2023

    @cache = {}

    module_function

    # Domingo de Páscoa (Meeus/Jones/Butcher, calendário gregoriano).
    def easter(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (19 * a + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month = (h + l - 7 * m + 114) / 31
      day = (h + l - 7 * m + 114) % 31 + 1
      Date.new(year, month, day)
    end

    def national(year)
      @cache[year] ||= begin
        easter_day = easter(year)
        days = FIXED.map { |month, day| Date.new(year, month, day) }
        days += [ easter_day - 2, easter_day - 48, easter_day - 47, easter_day + 60, Date.new(year, 12, 31) ]
        days.to_set
      end
    end

    def business?(date) = !date.saturday? && !date.sunday? && !national(date.year).include?(date)

    # O próprio dia, se útil; senão, o dia útil seguinte.
    def next_business(date)
      date += 1 until business?(date)
      date
    end
  end
end
