# Apresentação dos acordos (11): o selo da situação, a forma, os valores por componente e a tabela de parcelas.
module AgreementsHelper
  TONES = { "pending" => :warning, "approved" => :info, "refused" => :neutral, "not_approved" => :neutral, "expired" => :neutral, "canceled" => :neutral,
            "awaiting_effectuation" => :info, "active_on_time" => :success, "active_late" => :warning, "settled" => :success, "broken" => :danger, "renegotiated" => :neutral }.freeze

  def agreement_state(agreement)
    seal = situacao(t("agreements.states.#{agreement.state}"), tom: TONES.fetch(agreement.state))
    agreement.reversing? ? safe_join([ seal, " ", situacao("Em reversão", tom: :danger) ]) : seal
  end

  def agreement_mode(agreement) = t("agreements.mode_names.#{agreement.mode}")

  def component_name(component) = t("agreements.components.#{component}")

  # As colunas de componentes que uma tabela mostra, da última à primeira (principal primeiro): os cinco do valor atualizado e, só quando algum título tem, os herdados do acordo
  # sobre acordo (R250). `bases`: os hashes de base por componente das linhas da tabela.
  def component_columns(bases)
    Agreements::Caps::COMPONENTS.reverse.select { |component| !Agreements::INHERITED.include?(component) || bases.any? { |base| base.to_h.fetch(component, 0).to_i.positive? } }
  end

  # "Multa 50%, juros 50%" a partir dos descontos em centésimos de ponto; vazio quando não há desconto.
  def discounts_text(discounts_bp)
    parts = Agreements::Caps::COMPONENTS.filter_map do |component|
      bp = discounts_bp.to_h.fetch(component, 0).to_i
      "#{component_name(component).downcase} #{percent_bp(bp)}" if bp.positive?
    end
    parts.any? ? parts.join(", ") : "sem desconto"
  end

  # 5000 → "50%", 1250 → "12,5%".
  def percent_bp(bp)
    text = format("%.2f", bp / 100.0).sub(/0+\z/, "").sub(/\.\z/, "").tr(".", ",")
    "#{text}%"
  end

  def percent_decimal(text) = percent_bp((text.to_d * 100).round.to_i)

  # Número de um acordo em lista, com o link para a página dele.
  def agreement_link(agreement) = link_to(agreement.number, agreement_path(agreement))

  def channel_name(channel) = t("agreements.channels.#{channel}")

  # Propostas e acordos de um cliente: os números dos títulos.
  def agreement_bill_numbers(agreement) = agreement.agreement_bills.map { |row| row.bill.number }.to_sentence

  # Rótulo do valor de uma política de valor (tolerância ou mínimo): "R$ 1,00", "1,5%" ou o texto da opção.
  def policy_amount_text(value)
    case value["kind"]
    when "percent" then percent_bp(value["value"].to_i)
    when "tolerance" then t("agreements.policies.minimum_to_break.options.tolerance")
    else "R$ #{Money.format(value['value'].to_i)}"
    end
  end

  # Campo da política de valor no formulário: o valor guardado em reais ou em percentual, com vírgula.
  def policy_amount_field(value)
    return "" if value["kind"] == "tolerance"

    value["kind"] == "percent" ? format("%.2f", value["value"].to_i / 100.0).tr(".", ",") : Money.format(value["value"].to_i)
  end

  # A situação de um título de acordo na página do acordo (11, R225): a vencer, vencido, pago, cancelado ou aguardando a efetivação.
  def bill_title_state(bill, agreement)
    case bill.status
    when "paid" then situacao("Pago", tom: :success)
    when "canceled" then situacao("Cancelado", tom: :neutral)
    when "scheduled" then situacao("Aguardando efetivação", tom: :info)
    when "active" then bill.due_date < Date.current ? situacao("Vencido", tom: :danger) : situacao("A vencer", tom: :info)
    else situacao(t("agreements.bill_states.#{bill.status}", default: bill.status), tom: :neutral)
    end
  end
end
