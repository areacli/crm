# Tempo real com dados (decisão 0025, plano técnico seção 4). O que muda no servidor é publicado como (recurso, ids, credor); a tarefa
# monta, para cada usuário presente do credor, os registros que ele vê, pela mesma visão JSON da tela, e transmite no fluxo dele.
module Live
  # Acima disso, a mensagem só diz "recarregar" (lote grande: importação, recálculo).
  LIMITE = 200

  # Cada recurso registra como carrega os registros para um usuário: `->(user, ids) { escopo com os ids que ele vê }` e a visão JSON.
  RECURSOS = {}

  module_function

  def register(recurso, partial:, &scope)
    RECURSOS[recurso.to_s] = { partial: partial, scope: scope }
  end

  # Publica depois do commit da transação corrente (nada sai de uma transação desfeita).
  def publish(recurso, ids, tenant_id:)
    ids = Array(ids).compact.uniq
    return if ids.empty?

    ActiveRecord.after_all_transactions_commit { LiveBroadcastJob.perform_later(recurso.to_s, ids, tenant_id) }
  end

  # Usuários com vínculo ativo no credor (equipe do credor e pessoas da operação).
  def tenant_user_ids(tenant_id) = Membership.usable.where(tenant_id: tenant_id).distinct.pluck(:user_id)
end
