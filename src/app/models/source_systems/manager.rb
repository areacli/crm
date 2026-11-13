module SourceSystems
  # Sistemas do credor (17, R396 a R399) e a política "Cadastro entre sistemas" (R410): cria, renomeia, muda o tipo de chave, pausa, reativa
  # e exclui. A permissão 23 já foi conferida pela política no credor do sistema; as recusas das regras são do modelo (`SourceSystem`), e
  # cada mudança fica registrada com quem fez e quando (PD4).
  class Manager
    # Recusa de uma regra numa ação sem formulário (pausar, excluir): a mensagem vai à tela como está.
    class Refused < StandardError; end

    def initialize(actor) = @actor = actor

    def create(tenant:, name:, key_kind:)
      ApplicationRecord.transaction do
        tenant.source_systems.build(name: name, key_kind: key_kind, role: "remote").tap do |system|
          system.save!
          log(system, "created", nil, "#{system.name} (#{system.key_kind})")
        end
      end
    end

    # O tipo de chave só chega aqui enquanto o sistema não recebeu importação (R397); o modelo recusa depois disso.
    def update(system, name:, key_kind: system.key_kind)
      system.assign_attributes(name: name, key_kind: key_kind)
      ApplicationRecord.transaction do
        system.save!
        changes = system.saved_changes
        log(system, "renamed", changes["name"].first, system.name) if changes.key?("name")
        log(system, "key_kind_changed", changes["key_kind"].first, system.key_kind) if changes.key?("key_kind")
      end
      system
    end

    # Pausado, o sistema recusa importação nova; a que está em andamento termina (R398).
    def pause(system) = set_status(system, "paused")

    def resume(system) = set_status(system, "active")

    # R399: só o sistema sem importação, e nunca o CRM nem o Planilha.
    def destroy(system)
      ApplicationRecord.transaction do
        system.destroy or raise Refused, "#{system.errors.full_messages.to_sentence.upcase_first}."
        log(system, "destroyed", system.name, nil)
      end
    end

    # R410: quem prevalece no nome e nos dados do cliente quando dois sistemas o informam. Vale para as cargas seguintes.
    def update_customer_record_policy(tenant, policy:, system_id: nil)
      setting = tenant.setting
      system = tenant.source_systems.receiving.find_by(id: system_id) if policy.to_s == "defined_system"
      before = describe(setting)
      setting.update!(customer_record_policy: policy, customer_record_system: system)
      after = describe(setting)
      return setting if before == after

      Change.record!(tenant: tenant, user: @actor, subject_type: "settings", subject_id: tenant.id, event: "customer_record_policy_changed",
                     field: "customer_record_policy", before: before, after: after)
      setting
    end

    private
      def set_status(system, status)
        return system if system.status == status

        ApplicationRecord.transaction do
          system.update!(status: status)
          log(system, status == "paused" ? "paused" : "resumed", nil, system.name)
        end
        system
      rescue ActiveRecord::RecordInvalid => error
        raise Refused, "#{error.record.errors.full_messages.to_sentence.upcase_first}."
      end

      # O valor do histórico: a política e, quando há, o nome do sistema definido.
      def describe(setting)
        [ setting.customer_record_policy, setting.customer_record_system&.name ].compact.join(": ")
      end

      def log(system, event, before, after)
        Change.record!(tenant_id: system.tenant_id, user: @actor, subject_type: "source_system", subject_id: system.id, event: event, before: before, after: after)
      end
  end
end
