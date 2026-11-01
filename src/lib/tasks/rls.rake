# O `schema.rb` não guarda papéis nem políticas do RLS (decisão 0024): toda carga de esquema reinstala o que `Operations::Rls` declara.
%w[db:schema:load db:test:load_schema db:test:prepare db:prepare db:migrate].each do |name|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance do
    ActiveRecord::Base.connection_handler.connection_pool_list.each { |pool| pool.with_connection { |connection| Operations::Rls.install!(connection) } }
  end
end

namespace :crm do
  namespace :db do
    desc "Cria ou atualiza o papel de entrada da aplicação (crm_app) com a senha de DB_APP_PASSWORD; roda com a entrada do dono"
    task app_role: :environment do
      password = ENV.fetch("DB_APP_PASSWORD") { abort "Falta DB_APP_PASSWORD." }
      # Esta tarefa roda com a entrada do dono: a mesma senha nos dois é sinal de variável trocada (aconteceu no entrypoint, 31/10/2026).
      abort "DB_APP_PASSWORD é igual à senha do dono; o papel de entrada precisa de senha própria." if password == ENV["DB_PASSWORD"]
      Operations::Rls.create_login!(Operations::Rls::APP_ROLE, password)
      puts "Papel #{Operations::Rls::APP_ROLE} pronto."
    end
  end
end
