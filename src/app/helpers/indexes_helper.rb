# Formato dos índices na tela: porcentagem com vírgula, pelo menos duas casas e no máximo quatro.
module IndexesHelper
  def index_percent(value)
    return "—" if value.nil?

    text = value.to_d.to_s("F")
    text = text.sub(/(\.\d{2}\d*?)0+\z/, '\1')
    text = "#{text}0" if text.match?(/\.\d\z/)
    "#{text.tr('.', ',')}%"
  end

  def months_label(date) = date.strftime("%m/%Y")
end
