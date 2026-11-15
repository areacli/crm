# Textos e marcas das telas da régua (21): agenda, estado da rodada e do comando, e o cartão de cada ação no diagrama.
module CadencesHelper
  DAYS = %w[dom seg ter qua qui sex sáb].freeze
  ROUND_TONES = { "scheduled" => :info, "running" => :info, "completed" => :success, "completed_with_failures" => :warning, "failed" => :danger }.freeze
  # O ícone do Lucide de cada tipo (design system, revisão 25), na cor da família.
  ICONS = { "sms" => "message-square", "email" => "mail", "whatsapp" => "message-circle", "letter" => "scroll-text", "issue_instrument" => "receipt",
            "proposal" => "handshake", "promise" => "calendar-check", "task" => "clipboard-list", "negativation" => "ban", "protest" => "stamp",
            "lawsuit" => "gavel", "credit_suspension" => "lock" }.freeze
  ITEM_TONES = { "queued" => :info, "executed" => :success, "failed" => :danger, "no_return" => :warning, "discarded" => :neutral }.freeze

  # "Seg a sex, 9h30", "Todos os dias, 8h00", "Seg, qua e sex, 10h00".
  def agenda_da_regua(cadence)
    days = Array(cadence.schedule_days).sort
    hour, minute = cadence.schedule_time.split(":")
    time = "#{hour.to_i}h#{minute}"
    label = if days.size == 7 then "Todos os dias"
    elsif days == (1..5).to_a then "Seg a sex"
    else days.map { |day| DAYS[day] }.to_sentence(two_words_connector: " e ", last_word_connector: " e ").capitalize
    end
    "#{label}, #{time}#{' · sem feriado nacional' if cadence.skip_national_holidays}"
  end

  def situacao_da_rodada(round)
    label = t("cadences.round_states.#{round.state}")
    label = "#{label} · atrasada" if round.late? && !round.failed?
    situacao(label, tom: ROUND_TONES.fetch(round.state, :neutral))
  end

  def situacao_do_item(state) = situacao(t("cadences.item_states.#{state}"), tom: ITEM_TONES.fetch(state.to_s, :neutral))

  # O cartão da ação (protótipo): ícone e cor da família do tipo, o tipo e o parâmetro; no compacto, só o ícone, com o texto para o leitor de tela e
  # na dica do ponteiro.
  def cartao_da_acao(action, compact:)
    label = Cadences::Labels.action(action)
    inactive = !action.active_parameter?
    content = safe_join([ icone(ICONS.fetch(action.kind)), tag.span(label, class: (compact ? "apenas-leitor-de-tela" : "rotulo-da-acao")),
                          (tag.span(" (parâmetro inativo)", class: "apenas-leitor-de-tela") if inactive) ].compact)
    tag.span(content, class: "cartao-da-acao", data: { familia: Cadences::Diagram.family(action.kind), inativa: (true if inactive) }, title: (inactive ? "#{label} · parâmetro inativo" : label))
  end
end
