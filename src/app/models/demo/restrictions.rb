module Demo
  # O que a demonstração pública fecha e o que ela troca. Vale para qualquer usuário da instalação com CRM_DEMO=1:
  #
  # * fechado: usuários, perfis, troca de senha, cadastro do credor e contas de pagamento (credenciais) só se leem; qualquer alteração é recusada com mensagem;
  # * texto digitado: o que o visitante escreve em campo livre (texto e contato do acionamento, motivos, notas, nome e contatos do cliente) é trocado por texto
  #   fictício antes de chegar ao serviço, para a vitrine não guardar dado pessoal de ninguém (LGPD). O que o credor define (nome de canal, de resultado, de
  #   segmento) continua como foi digitado até a recriação das 4h.
  module Restrictions
    MESSAGE = "Na demonstração pública, usuários, perfis, senhas, dados do credor e contas de pagamento ficam fechados: dá para ver, não para alterar.".freeze
    TEXT = "texto descartado na demonstração".freeze
    CONTACT = "contato descartado na demonstração".freeze
    REASON = "motivo descartado na demonstração".freeze

    # Controladores fechados para qualquer método que não seja de leitura.
    CLOSED_WRITES = %w[memberships memberships/profiles memberships/activations memberships/password_resets profiles settings/tenant_registries
                       settings/payment_accounts settings/payment_accounts/activations settings/payment_accounts/webhook_secrets settings/payment_accounts/connection_tests
                       settings/channels/webhook_secrets].freeze
    # Fechados também para leitura (a tela só existe para alterar).
    CLOSED_ALL = %w[passwords].freeze
    CLOSED_ACTIONS = [ [ "settings/payment_accounts", "new" ] ].freeze

    # [controlador, ação] => { grupo de parâmetros => { campo => texto que o substitui } }
    SCRUB = {
      [ "customers/contact_attempts", "create" ] => { "contact_attempt" => { "text" => TEXT, "contact_used" => CONTACT, "save_contact" => "0" } },
      [ "customers/credit_transfers", "create" ] => { "credit_transfer" => { "reason" => REASON } },
      [ "customer_contacts/statuses", "update" ] => { "status" => { "reason" => REASON } },
      [ "reversal_waits", "update" ] => { "decision" => { "note" => REASON } },
      [ "value_discrepancies/handlings", "create" ] => { "handling" => { "note" => REASON } },
      [ "promises/refusals", "create" ] => { "promise" => { "reason" => REASON } },
      [ "agreements/refusals", "create" ] => { "agreement" => { "reason" => REASON } },
      [ "agreements/acceptances", "create" ] => { "acceptance" => { "proof" => TEXT } },
      [ "customers/data_exports", "create" ] => { "export" => { "reason" => REASON } },
      [ "customers/retentions", "create" ] => { "retention" => { "reason" => REASON } },
      [ "customers/anonymizations", "create" ] => { "anonymization" => { "reason" => REASON } },
      [ "settings/index_adjustments", "create" ] => { "adjustment" => { "reason" => REASON } }
    }.freeze

    module_function

    def closed?(controller_path, action_name, request_method)
      return true if CLOSED_ALL.include?(controller_path) || CLOSED_ACTIONS.include?([ controller_path, action_name ])

      CLOSED_WRITES.include?(controller_path) && !%w[GET HEAD].include?(request_method)
    end

    # Troca, nos parâmetros do pedido, o que o visitante digitou. Só mexe no que veio preenchido.
    def scrub!(params, controller_path, action_name)
      key = [ controller_path, action_name ]
      SCRUB.fetch(key, {}).each do |group, fields|
        next unless params[group].respond_to?(:key?)

        fields.each { |field, text| params[group][field] = text if params[group].key?(field) && params[group][field].to_s.strip.present? || field == "save_contact" && params[group].key?(field) }
      end
      scrub_customer!(params, key)
    end

    # Nome do cliente e contatos do cadastro: valores fictícios do mesmo formato (o telefone continua telefone, o endereço continua endereço).
    def scrub_customer!(params, key)
      case key
      when [ "customers/names", "update" ]
        params[:customer][:name] = "Cliente fictício #{SecureRandom.random_number(10_000)}" if params[:customer].respond_to?(:key?) && params[:customer][:name].present?
      when [ "customer_contacts", "create" ], [ "customer_contacts", "update" ]
        contact = params[:contact]
        return unless contact.respond_to?(:key?)

        kind = contact[:kind].presence || CustomerContact.find_by(id: params[:id])&.kind
        seed = SecureRandom.random_number(90_000_000)
        case kind
        when "phone" then contact[:value] = "(11) 9#{(10_000_000 + seed).to_s[0, 4]}-#{(1000 + seed % 9000)}"
        when "email" then contact[:value] = "contato#{seed}@exemplo.com.br"
        when "address"
          contact.merge!(street: "Rua da Demonstração", number: "100", complement: "", district: "Centro", city: "São Paulo", state: "SP", zip: "01001000") if contact.key?(:street)
        end
      end
    end
  end
end
