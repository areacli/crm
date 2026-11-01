module Operations
  # Aviso à operação quando outra origem desfaz algo dela (14, R318): o aceite de um acordo que cancela a promessa dela (11, R222) e a proposta
  # nova que substitui a proposta dela (11, R218). O aviso vai a quem criou o registro, no sino.
  module UndoNotice
    module_function

    def call(record, actor, number:)
      return unless record.operation_id && record.user_id
      return if actor && actor.operation&.id == record.operation_id

      Notice.create!(user_id: record.user_id, kind: "operation_undone",
                     data: { number: number, actor_name: actor&.name || "o sistema", tenant_name: record.tenant.name })
    end
  end
end
