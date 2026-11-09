module Operations
  # Quem age, para o RLS (decisão 0024): no começo de cada requisição, o papel do banco (`crm_operation` com a operação do usuário, ou `crm_team`
  # para a equipe do credor e quem não entrou); no fim, de volta ao papel da conexão, para não passar ao próximo pedido. `system` abre um trecho
  # que vê tudo, para os serviços de domínio que mexem além do que está pra o usuário (efeitos do aceite de acordo, recálculos, o próprio alcance).
  module Context
    module_function

    def for_user(user)
      operation = user&.operation
      apply(operation ? "crm_operation" : "crm_team", operation&.id, user&.id)
      yield
    rescue ActiveRecord::RecordNotFound
      # 14, R313 e R320: o que não está pra operação responde "não encontrado", e a tentativa fica na trilha.
      Trail.record("not_found", user: user) if operation
      raise
    ensure
      reset
    end

    def system
      previous = Thread.current[:crm_db_role]
      return yield if previous&.first == "crm_team"
      # Fora de requisição e de tarefa (console, tarefa rake): o papel de entrada não vê a carteira, então o trecho declara a equipe.
      return for_user(nil) { yield } if previous.nil?

      apply("crm_team", nil, previous.last)
      begin
        yield
      ensure
        apply(*previous)
      end
    end

    # Trecho de uma tarefa que responde por quem a pediu (14, R314): o usuário de operação só resolve o que está pra ele, como na requisição. A
    # equipe do credor não muda de papel.
    def acting_as(user)
      operation = user&.operation or return yield

      previous = Thread.current[:crm_db_role]
      apply("crm_operation", operation.id, user.id)
      begin
        yield
      ensure
        previous ? apply(*previous) : reset
      end
    end

    # Console, `runner` e tarefas rake (decisão 0024): com a entrada sem privilégios (produção), declaram a equipe, como o sistema; com a do
    # dono, nada.
    def declare_entry_role!
      apply("crm_team", nil, nil) unless ActiveRecord::Base.connection.select_value("SELECT rolsuper FROM pg_roles WHERE rolname = current_user")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      # `db:create` e afins carregam o ambiente antes de o banco existir.
      nil
    end

    def operation? = Thread.current[:crm_db_role]&.first == "crm_operation"

    # A operação de quem age nesta requisição: a origem do que ele cria (14, R315).
    def operation_id = operation? ? Thread.current[:crm_db_role][1] : nil

    def apply(role, operation_id, user_id)
      connection = ActiveRecord::Base.connection
      connection.execute("SET ROLE #{connection.quote_column_name(role)}")
      # O corte da exposição "vencidas" de cada credor da operação (R319), para a política das faturas.
      cutoffs = operation_id ? ReachBuilder.cutoffs(operation_id).to_json : ""
      connection.exec_query("SELECT set_config('crm.operation', $1, false), set_config('crm.user', $2, false), set_config('crm.cutoffs', $3, false)", "Operations::Context",
                            [ operation_id.to_s, user_id.to_s, cutoffs ].map { |value| ActiveRecord::Relation::QueryAttribute.new("v", value, ActiveRecord::Type::String.new) })
      Thread.current[:crm_db_role] = [ role, operation_id, user_id ]
    end

    def reset
      return unless Thread.current[:crm_db_role]

      connection = ActiveRecord::Base.connection
      connection.execute("RESET ROLE")
      connection.execute("SELECT set_config('crm.operation', '', false), set_config('crm.user', '', false), set_config('crm.cutoffs', '', false)")
    ensure
      Thread.current[:crm_db_role] = nil
    end
  end
end
