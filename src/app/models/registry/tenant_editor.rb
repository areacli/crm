module Registry
  # Dados do credor (R106): quem tem "alterar configuração" no credor edita o cadastro; cada mudança vai ao histórico (antes, depois, quem,
  # quando). Mudar o telefone ou o e-mail do credor invalida os contatos de clientes que são iguais a eles (R126), com registro.
  class TenantEditor
    def initialize(actor) = @actor = actor

    # Devolve o credor. Cadastro inválido levanta ActiveRecord::RecordInvalid com as mensagens no próprio credor.
    def update(tenant, attributes)
      tenant.assign_attributes(attributes.to_h.symbolize_keys.slice(*Tenant::REGISTRY_FIELDS))
      before = Tenant::REGISTRY_FIELDS.index_with { |field| tenant.attribute_in_database(field) }
      old_keys = { "phone" => tenant.phone_key, "email" => tenant.email_key }
      ApplicationRecord.transaction do
        tenant.save!(context: :registry)
        before.each do |field, value|
          after = tenant[field]
          next if value.to_s == after.to_s

          Change.create!(tenant_id: tenant.id, user: @actor, subject_type: "tenant", subject_id: tenant.id, event: "registry_changed", field: field.to_s,
                         before: value, after: after, origin: "screen")
        end
        { "phone" => tenant.phone_key, "email" => tenant.email_key }.each do |kind, key|
          invalidate_equal_contacts(tenant, kind, key) if key.present? && key != old_keys[kind]
        end
      end
      tenant
    end

    private
      # R126: contatos de clientes do credor iguais ao contato dele passam a inválidos, com o motivo e o registro no histórico.
      def invalidate_equal_contacts(tenant, kind, key)
        Portfolio::Sql.run(<<~SQL, @actor.id, tenant.id, kind, key)
          with changed as (
            update customer_contacts set status = 'invalid', reason = 'é contato do credor', do_not_disturb_on = null, updated_at = now(), updated_by_id = ?
            where tenant_id = ? and kind = ? and key = ? and status <> 'invalid'
            returning id, old.status as before_status
          )
          insert into changes (tenant_id, user_id, subject_type, subject_id, event, field, before, after, note, origin, occurred_at)
          select #{tenant.id.to_i}, #{@actor.id.to_i}, 'customer_contact', id, 'status_changed', 'status', before_status, 'invalid', 'é contato do credor', 'screen', now() from changed
        SQL
      end
  end
end
