module Contacts
  # Registro de acionamentos (04, R69 a R73, R77). A permissão (7 e 1) já foi conferida pela política, no credor do cliente (R76); aqui ficam as
  # regras de dados, e cada registro vai ao histórico de alterações. O acionamento é imutável: quem errou registra outro, com a observação.
  class Recorder
    MAX_PAST_DAYS = 7
    MAX_RETURN_DAYS = 90
    MAX_TEXT = 2000
    # Duplo clique ou recarga: o mesmo registro do mesmo usuário em até 10 segundos é ignorado.
    DUPLICATE_WINDOW = 10.seconds
    # Tamanho do contato usado por canal (R71): telefone e mensagem 60, e-mail 254, carta, presencial e outro 300.
    CONTACT_LIMITS = { "phone" => 60, "whatsapp" => 60, "sms" => 60, "email" => 254 }.freeze
    # Caracteres de controle invisíveis (R72); a quebra de linha (\n) e a tabulação (\t) ficam.
    INVISIBLE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁠﻿]/

    def initialize(actor) = @actor = actor

    # `attributes`: channel, result_id, contract_id, contact_used, text, contacted_at e return_at (estes dois como o campo de data e hora
    # envia). Devolve o acionamento criado, ou o idêntico já registrado há pouco (duplo envio).
    def record(customer, attributes, save_contact: false)
      raise Refused, I18n.t("titular.anonymized_customer") if customer.anonymized?

      channel = attributes[:channel].to_s
      refuse!(:channel) unless ContactAttempt::CHANNELS.include?(channel)
      result = ContactResult.find_by(id: attributes[:result_id], tenant_id: customer.tenant_id)
      refuse!(:result) unless result
      refuse!(:result_inactive) unless result.active?
      contract = find_contract(customer, attributes[:contract_id])

      now = Time.current
      informed = parse_time(attributes[:contacted_at])
      contacted_at = informed || now
      refuse!(:future_contact) if contacted_at > now + 1.minute
      refuse!(:past_contact, days: MAX_PAST_DAYS) if contacted_at < (now - MAX_PAST_DAYS.days).beginning_of_minute
      return_at = check_return(result, contacted_at, parse_time(attributes[:return_at]))

      text = clean(attributes[:text])
      refuse!(:text_too_long, max: MAX_TEXT) if text && text.length > MAX_TEXT
      contact = clean(attributes[:contact_used])&.squish
      limit = CONTACT_LIMITS.fetch(channel, 300)
      refuse!(:contact_too_long, max: limit) if contact && contact.length > limit

      duplicate = ContactAttempt.where(customer_id: customer.id, user_id: @actor.id, channel: channel, result_id: result.id, contract_id: contract&.id, contact_used: contact, text: text)
                                .where(created_at: (now - DUPLICATE_WINDOW)..)
      duplicate = duplicate.where(contacted_at: informed) if informed
      return duplicate.first if duplicate.exists?

      ApplicationRecord.transaction do
        ContactAttempt.create!(tenant_id: customer.tenant_id, customer: customer, contract: contract, user: @actor, result: result, result_kind: result.kind,
                               channel: channel, contact_used: contact, text: text, contacted_at: contacted_at, return_at: return_at).tap do |attempt|
          log(attempt, "created", nil, result.name)
          apply_to_registry(customer, attempt, result, save_contact)
        end
      end
    end

    # R120 (DC2): o aviso de contato inválido ou em "não perturbe" digitado no registro; o acionamento é aceito do mesmo jeito. Nil se não há aviso.
    def self.contact_warning(customer, channel, text)
      contact = Registry::ContactEditor.find_used(customer, channel, clean(text)&.squish)
      return if contact.nil? || contact.status_valid?

      if contact.status_do_not_disturb?
        I18n.t("registry.attempt_warning.do_not_disturb", date: (contact.do_not_disturb_on || contact.updated_at.to_date).strftime("%d/%m/%Y"))
      else
        I18n.t("registry.attempt_warning.invalid", reason: contact.reason.to_s.presence || "sem motivo registrado")
      end
    end

    # R72: texto puro. Caracteres de controle invisíveis saem; as quebras de linha ficam (e viram \n).
    def self.clean(text)
      cleaned = text.to_s.gsub(/\r\n?/, "\n").gsub(INVISIBLE, "").strip
      cleaned.presence
    end

    private
      # R121 e R122: o resultado que invalida o contato marca o contato usado; "salvar este contato no cadastro" (só com a permissão 12, conferida
      # por quem chama) cria o contato digitado, de origem acionamento.
      def apply_to_registry(customer, attempt, result, save_contact)
        return if attempt.contact_used.blank?

        editor = Registry::ContactEditor.new(@actor)
        if result.invalidates_contact?
          editor.invalidate_used(customer, attempt.channel, attempt.contact_used, on: attempt.contacted_at.to_date)
        elsif save_contact
          editor.save_from_attempt(customer, attempt.channel, attempt.contact_used)
        end
      end

      def clean(text) = self.class.clean(text)

      def refuse!(key, **options) = raise(Refused, I18n.t("contacts.refused.#{key}", **options))

      # R69b: o contrato é opcional, do mesmo credor, e o cliente tem de figurar nele.
      def find_contract(customer, id)
        return if id.blank?

        contract = Contract.find_by(id: id, tenant_id: customer.tenant_id)
        refuse!(:customer_not_in_contract) unless contract && ContractCustomer.exists?(contract_id: contract.id, customer_id: customer.id)
        contract
      end

      # R73: a regra do resultado manda; o retorno é depois do contato e até 90 dias.
      def check_return(result, contacted_at, return_at)
        refuse!(:return_not_allowed) if result.return_not_allowed? && return_at
        refuse!(:return_required) if result.return_required? && return_at.nil?
        return unless return_at
        refuse!(:return_before_contact) if return_at <= contacted_at
        refuse!(:return_too_far, days: MAX_RETURN_DAYS) if return_at > contacted_at + MAX_RETURN_DAYS.days
        return_at
      end

      # O campo de data e hora do formulário (AAAA-MM-DDTHH:MM) ou vazio; texto que não é data é recusado.
      def parse_time(raw)
        return if raw.blank?

        Time.zone.parse(raw.to_s) or refuse!(:invalid_time)
      rescue ArgumentError
        refuse!(:invalid_time)
      end

      def log(attempt, event, before, after)
        Change.create!(tenant_id: attempt.tenant_id, user: @actor, subject_type: "contact_attempt", subject_id: attempt.id, event: event, before: before, after: after)
      end
  end
end
