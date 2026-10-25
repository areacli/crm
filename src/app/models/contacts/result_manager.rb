module Contacts
  # Lista de resultados do credor (R66, R67): cria, renomeia, muda a regra de retorno, ordena e desativa. A permissão 9 já foi conferida
  # pela política no credor do resultado. O tipo não muda depois de criado e nada se apaga; cada mudança fica registrada (R77).
  class ResultManager
    def initialize(actor) = @actor = actor

    # Resultado novo entra no fim da lista (revisão 2).
    def create(tenant:, name:, kind:, return_rule:, invalidates_contact: false)
      ApplicationRecord.transaction do
        position = tenant.contact_results.maximum(:position).to_i + 1
        tenant.contact_results.build(name: name, kind: kind, return_rule: return_rule, position: position, invalidates_contact: invalidates_contact).tap do |result|
          result.save!
          log(result, "created", nil, result.name)
        end
      end
    end

    def update(result, name:, return_rule:, invalidates_contact: result.invalidates_contact)
      result.assign_attributes(name: name, return_rule: return_rule, invalidates_contact: invalidates_contact)
      ApplicationRecord.transaction do
        result.save!
        changes = result.saved_changes
        log(result, "renamed", changes["name"].first, result.name) if changes.key?("name")
        log(result, "return_rule_changed", changes["return_rule"].first, result.return_rule) if changes.key?("return_rule")
        log(result, "invalidates_contact_changed", changes["invalidates_contact"].first.to_s, result.invalidates_contact.to_s) if changes.key?("invalidates_contact")
      end
      result
    end

    # Desativa ou reativa (R67): o resultado desativado some da escolha e continua nos acionamentos antigos.
    def set_active(result, active)
      return result if result.active == active

      ApplicationRecord.transaction do
        result.update!(active: active)
        log(result, active ? "reactivated" : "deactivated", nil, result.name)
      end
      result
    end

    # Troca de lugar com o vizinho, sem arrastar (revisão 2, WCAG 2.5.7). `direction`: "up" ou "down".
    def move(result, direction)
      ApplicationRecord.transaction do
        siblings = result.tenant.contact_results.lock.ordered.to_a
        index = siblings.index { |other| other.id == result.id }
        target = direction.to_s == "up" ? index - 1 : index + 1
        next result if target.negative? || target >= siblings.size

        siblings[index], siblings[target] = siblings[target], siblings[index]
        siblings.each_with_index { |other, position| other.update_columns(position: position + 1) if other.position != position + 1 }
        log(result, "moved", (index + 1).to_s, (target + 1).to_s)
        result.reload
      end
    end

    private
      def log(result, event, before, after)
        Change.create!(tenant_id: result.tenant_id, user: @actor, subject_type: "contact_result", subject_id: result.id, event: event, before: before, after: after)
      end
  end
end
