module Registry
  # Edição de contatos e do nome do cliente pela tela (R113 a R116) e pelo acionamento (R122). A permissão (12 e 1, no credor do cliente) já
  # foi conferida pela política; aqui ficam as regras de dados. Tudo o que se faz na tela recebe a marca "mantido pelo credor" e cada mudança
  # vai ao histórico do cadastro (R116), com quem, quando, a origem e o motivo.
  class ContactEditor
    MAX_REASON = 300
    LIMITS = { "phone" => 60, "email" => 254 }.freeze
    NAME_LIMIT = 300

    def initialize(actor) = @actor = actor

    # Acrescenta um contato (R113). `fields`: `value` para telefone e e-mail; os campos do endereço para `address`. Devolve o contato.
    def add(customer, kind:, fields:, origin: "screen")
      parsed = parse!(kind, fields)
      ApplicationRecord.transaction do
        refuse_existing!(customer, parsed)
        create_contact(customer, parsed, origin: origin, kept: origin == "screen")
      end
    end

    # Corrige um contato (R113): o antigo vira inválido ("corrigido para ...") e nasce o novo, origem tela. Devolve o novo.
    def correct(contact, kind_fields)
      raise Refused, t(:invalid_cannot_be_corrected) if contact.status_invalid?

      customer = contact.customer
      parsed = parse!(contact.kind, kind_fields)
      raise Refused, t(:same_as_current) if parsed.key == contact.key

      ApplicationRecord.transaction do
        refuse_existing!(customer, parsed)
        change_status(contact, "invalid", reason: "corrigido para #{parsed.value}", event: "corrected")
        create_contact(customer, parsed, origin: "screen", kept: true)
      end
    end

    # Marca inválido, com motivo (R113).
    def mark_invalid(contact, reason)
      reason = clean_reason(reason, required: true)
      raise Refused, t(:already_invalid) if contact.status_invalid?

      ApplicationRecord.transaction { change_status(contact, "invalid", reason: reason) }
    end

    # Marca "não perturbe" a pedido do cliente, com a data do pedido (R113, R114): vale por contato, sem prazo.
    def do_not_disturb(contact, requested_on, note = nil)
      date = parse_date(requested_on)
      raise Refused, t(:only_valid_can_be_dnd) unless contact.status_valid?

      ApplicationRecord.transaction { change_status(contact, "do_not_disturb", reason: clean_reason(note), requested_on: date) }
    end

    # Volta a válido, com motivo (R113). O contato igual ao do credor não volta (R126).
    def restore(contact, reason)
      reason = clean_reason(reason, required: true)
      raise Refused, t(:already_valid) if contact.status_valid?
      raise Refused, t(:tenant_contact) if tenant_contact?(contact.tenant, contact.kind, contact.key)

      ApplicationRecord.transaction { change_status(contact, "valid", reason: reason) }
    end

    # Corrige o nome do cliente (R113): fica "mantido pelo credor". O documento não se edita (R115).
    def rename(customer, name)
      name = name.to_s.squish
      raise Refused, t(:name_required) if name.empty?
      raise Refused, t(:name_too_long, max: NAME_LIMIT) if name.length > NAME_LIMIT
      return customer if name == customer.name && customer.name_kept?

      ApplicationRecord.transaction do
        before = customer.name
        customer.update!(name: name, name_kept: true)
        log(customer.tenant_id, "customer", customer.id, "name_changed", "name", before, name) if before != name
      end
      customer
    end

    # Contato digitado no acionamento que o operador mandou salvar (R122): nasce válido, origem acionamento. Se já existir, não duplica
    # (devolve o existente); texto que não é contato válido do tipo do canal não é salvo e o acionamento segue (DC2: o registro vale).
    def save_from_attempt(customer, channel, text)
      kind = CustomerContact::CHANNEL_KINDS[channel] or return
      return if kind == "address"

      parsed = Normalizer.public_send(kind, text)
      return unless parsed.is_a?(ParsedContact)

      customer.contacts.find_by(kind: kind, key: parsed.key) || create_contact(customer, parsed, origin: "contact_attempt", kept: false)
    end

    # O contato cadastrado do cliente que corresponde ao contato usado num acionamento (texto livre): telefone e e-mail pela forma normalizada
    # (R125), endereço pelo texto como foi oferecido. Nil se o contato não está cadastrado.
    def self.find_used(customer, channel, text)
      kind = CustomerContact::CHANNEL_KINDS[channel]
      return if kind.nil? || text.blank?
      return customer.contacts.address.detect { |candidate| FoldedText.fold(candidate.value) == FoldedText.fold(text) } if kind == "address"

      key = Normalizer.key_for(kind, text)
      key && customer.contacts.find_by(kind: kind, key: key)
    end

    # R121: o resultado que invalida o contato marca como inválido o contato cadastrado que foi usado, com o motivo e a data do acionamento.
    def invalidate_used(customer, channel, text, on:)
      contact = self.class.find_used(customer, channel, text)
      return if contact.nil? || contact.status_invalid?

      change_status(contact, "invalid", reason: "inexistente, acionamento de #{on.strftime('%d/%m')}", event: "invalidated_by_result", kept: false)
    end

    private
      def t(key, **options) = I18n.t("registry.refused.#{key}", **options)

      def parse!(kind, fields)
        kind = kind.to_s
        raise Refused, t(:kind) unless CustomerContact.kinds.key?(kind)

        fields = fields.to_h.symbolize_keys
        if kind == "address"
          result = Normalizer.address(fields.slice(*Tenant::ADDRESS_FIELDS)) or raise Refused, t(:address_blank)
        else
          raw = fields[:value].to_s.strip
          raise Refused, t(:value_required) if raw.empty?
          raise Refused, t(:too_long, max: LIMITS.fetch(kind)) if raw.length > LIMITS.fetch(kind)

          result = Normalizer.public_send(kind, raw)
        end
        raise Refused, t(:invalid_format, kind: I18n.t("registry.kinds.#{kind}"), reason: result) if result.is_a?(String)

        result
      end

      def refuse_existing!(customer, parsed)
        existing = customer.contacts.find_by(kind: parsed.kind, key: parsed.key) or return

        raise Refused, t(:already_registered, status: I18n.t("registry.statuses.#{existing.status}").downcase)
      end

      def tenant_contact?(tenant, kind, key)
        (kind == "phone" && tenant.phone_key == key) || (kind == "email" && tenant.email_key == key)
      end

      def create_contact(customer, parsed, origin:, kept:)
        tenant_contact = tenant_contact?(customer.tenant, parsed.kind, parsed.key)
        contact = customer.contacts.create!(parsed.address_attributes.merge(tenant_id: customer.tenant_id, kind: parsed.kind, key: parsed.key, value: parsed.value, origin: origin,
                                                                           status: tenant_contact ? "invalid" : "valid", reason: tenant_contact ? "é contato do credor" : nil,
                                                                           kept_by_tenant: kept, updated_by: @actor))
        log(contact.tenant_id, "customer_contact", contact.id, "created", "status", nil, contact.status, note: contact.reason, origin: origin == "screen" ? "screen" : "contact_attempt")
        contact
      end

      def change_status(contact, status, reason:, event: "status_changed", requested_on: nil, kept: true)
        before = contact.status
        contact.update!(status: status, reason: reason, do_not_disturb_on: requested_on, kept_by_tenant: kept || contact.kept_by_tenant, updated_by: @actor)
        log(contact.tenant_id, "customer_contact", contact.id, event, "status", before, status,
            note: [ reason, (requested_on ? "pedido em #{requested_on.strftime('%d/%m/%Y')}" : nil) ].compact.join("; ").presence, origin: event == "invalidated_by_result" ? "contact_attempt" : "screen")
        contact
      end

      def clean_reason(text, required: false)
        text = text.to_s.squish
        raise Refused, t(:reason_required) if required && text.empty?
        raise Refused, t(:reason_too_long, max: MAX_REASON) if text.length > MAX_REASON

        text.presence
      end

      def parse_date(raw)
        date = Date.iso8601(raw.to_s)
        raise Refused, t(:future_date) if date > Date.current

        date
      rescue Date::Error
        raise Refused, t(:invalid_date)
      end

      def log(tenant_id, subject_type, subject_id, event, field, before, after, note: nil, origin: "screen")
        Change.record!(tenant_id: tenant_id, user: @actor, subject_type: subject_type, subject_id: subject_id, event: event, field: field, before: before, after: after,
                       note: note, origin: origin)
      end
  end
end
