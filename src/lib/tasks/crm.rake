namespace :crm do
  desc "Verifica a plataforma: um job em cada fila do Sidekiq, cada um transmitindo um sinal no canal platform"
  task platform_check: :environment do
    PlatformCheckJob::QUEUES.each do |queue|
      PlatformCheckJob.set(queue: queue).perform_later(queue)
      puts "job enfileirado na fila #{queue}"
    end
  end
end

namespace :crm do
  desc "Administra usuários (R43): crm:user[create|link|rename|list|deactivate|reactivate|reset_password,e-mail] com NAME, TENANT, PROFILE e PASSWORD no ambiente"
  task :user, [ :action, :email_address ] => :environment do |_task, args|
    puts Access::AdminCommand.new.run(args[:action], args[:email_address], name: ENV["NAME"], tenant: ENV["TENANT"], profile: ENV["PROFILE"], password: ENV["PASSWORD"])
  rescue Access::Refused => error
    abort error.message
  end

  desc "Cria um credor com a configuração inicial e os perfis Gestor e Operador (MT-21): crm:tenant[Nome do credor]"
  task :tenant, [ :name ] => :environment do |_task, args|
    abort "Informe o nome do credor." if args[:name].blank?
    abort "Já existe um credor com esse nome." if Tenant.exists?(name: args[:name])

    tenant = Tenant.provision!(args[:name])
    AccessEvent.record("admin_tenant_created", tenant: tenant, details: { name: tenant.name })
    puts "Credor #{tenant.name} criado com os perfis Gestor e Operador."
  end
end
