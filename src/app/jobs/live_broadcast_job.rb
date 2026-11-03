# Monta e transmite a mensagem de tempo real de cada usuário presente do credor (decisão 0025). Cada usuário roda no próprio contexto:
# o papel do banco (RLS, especificação 14) e as políticas dele. O que ele não vê (ou deixou de ver) vai em `removidos`, sem dado.
class LiveBroadcastJob < ApplicationJob
  queue_as :default

  def perform(recurso, ids, tenant_id)
    definicao = Live::RECURSOS.fetch(recurso)
    User.where(id: Live::Presence.present_user_ids(Live.tenant_user_ids(tenant_id))).find_each do |user|
      LiveChannel.broadcast_to(user, message_for(user, recurso, definicao, ids))
    end
  end

  private
    def message_for(user, recurso, definicao, ids)
      return { recurso: recurso, acao: "recarregar" } if ids.size > Live::LIMITE

      Operations::Context.for_user(user) do
        # `Current.user` vem da sessão: uma sessão em memória, não gravada, só para as visões e as políticas saberem quem é.
        Current.set(session: Session.new(user: user)) do
          registros = definicao[:scope].call(user, ids).to_a
          json = ApplicationController.render(partial: definicao[:partial], formats: :json, locals: { registros: registros, user: user })
          { recurso: recurso, acao: "atualizar", registros: JSON.parse(json), removidos: ids - registros.map(&:id) }
        end
      end
    end
end
