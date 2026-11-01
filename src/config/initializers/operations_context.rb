# Papel do banco das tarefas em segundo plano (decisão 0024; `Operations::JobContext`). Depois da inicialização: o middleware é uma classe
# da aplicação, que os inicializadores ainda não carregam.
Rails.application.config.after_initialize do
  Sidekiq.configure_server do |config|
    config.server_middleware { |chain| chain.add Operations::JobContext }
  end
end

# Em produção a entrada é o papel sem privilégios, que não lê a carteira sem declarar um papel: as tarefas rake (como as do sistema) declaram a
# equipe ao carregar o ambiente. Com a entrada do dono (desenvolvimento, teste, migrações) nada muda. O console e o `runner` estão em
# config/application.rb.
Rails.application.config.after_initialize do
  Operations::Context.declare_entry_role! if defined?(Rake.application) && Rake.application.top_level_tasks.any?
end
