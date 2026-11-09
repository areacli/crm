module Operations
  # Middleware do Sidekiq (decisão 0024): toda tarefa em segundo plano roda como o sistema (`crm_team`), porque o papel de entrada da aplicação
  # não lê a carteira sem declarar um papel. As tarefas não agem como um usuário de operação: o que elas fazem por um usuário foi conferido
  # na requisição que as pediu.
  class JobContext
    include Sidekiq::ServerMiddleware

    # Pelo nome completo: o Sidekiq guarda esta classe, e em desenvolvimento a recarga do código deixaria o `Context` do escopo antigo sem definição.
    def call(_job_instance, _job, _queue, &) = Operations::Context.for_user(nil, &)
  end
end
