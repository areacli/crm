module Cadences
  # O retorno do executor, por item (21, R439, R441): executado (com um detalhe curto) ou falhou (com o motivo); falhou é final. O item na fila ou
  # "sem retorno" recebe o retorno que chegar; o que já tem retorno não muda. O comando resume os itens.
  module Returns
    OPEN = %w[queued no_return].freeze
    # O descarte que desfaz o disparo (R434): a coluna volta a valer na rodada seguinte.
    UNDO_FIRING = %w[moved_lane cadence_off].freeze

    module_function

    def executed(item, detail) = record(item, "executed", detail: detail)
    def failed(item, reason) = record(item, "failed", reason: reason)

    def record(item, state, detail: nil, reason: nil, payment_instrument: nil)
      changed = CadenceCommandItem.where(id: item.id, state: OPEN)
                                  .update_all(state: state, detail: detail&.truncate(300), reason: reason&.truncate(300), returned_at: Time.current,
                                              payment_instrument_id: payment_instrument&.id, updated_at: Time.current)
      changed.positive?
    end

    # Descartado pelo "ainda vale?" (R438), com o motivo; "mudou de raia" e "régua desligada" desfazem o disparo da coluna se nenhum outro item
    # vivo da mesma coluna e episódio o sustenta.
    def discard(item, reason, kind)
      return false unless record(item, "discarded", reason: reason)

      undo_firing(item.decision) if UNDO_FIRING.include?(kind)
      true
    end

    def undo_firing(decision)
      alive = CadenceCommandItem.joins(:decision).where(cadence_decisions: { cadence_id: decision.cadence_id, object_key: decision.object_key,
                                                                             episode_key: decision.episode_key, cadence_column_id: decision.cadence_column_id })
                                .where.not(state: "discarded")
      return if alive.exists?

      CadenceFiring.where(cadence_id: decision.cadence_id, object_key: decision.object_key, episode_key: decision.episode_key,
                          cadence_column_id: decision.cadence_column_id).delete_all
    end

    # O estado do comando é o resumo dos itens (R441).
    def refresh_command(command)
      states = command.items.pluck(:state)
      state = if states.include?("queued") then "queued"
      elsif states.include?("no_return") then "no_return"
      elsif states.include?("executed") then "executed"
      elsif states.include?("failed") then "failed"
      else "discarded"
      end
      command.update_columns(state: state, updated_at: Time.current)
    end
  end
end
