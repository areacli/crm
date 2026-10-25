# Formatos do sistema (design system, seção 8): moeda, número, data e data com hora, todos no padrão brasileiro e em Brasília.
module FormattingHelper
  def money(cents) = "R$ #{Money.format(cents)}"

  def number_br(value) = value.to_i.to_s.reverse.scan(/\d{1,3}/).join(".").reverse

  def date_br(date) = date&.strftime("%d/%m/%Y")

  def datetime_br(time) = time&.in_time_zone&.strftime("%d/%m/%Y %H:%M")
end
