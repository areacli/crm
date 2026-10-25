namespace :crm do
  desc "Cria os dados fictícios da demonstração sobre um banco vazio (credores Alfa e Beta, usuários públicos, carteira, pagamentos...)"
  task demo_data: :environment do
    abort "Recusado: o modo de demonstração não está ligado (CRM_DEMO=1)." unless Demo.enabled?
    abort "Já existem credores; use crm:demo_reset para apagar e recriar." if Tenant.exists?

    started = Time.current
    Demo::Dataset.new(log: ->(message) { puts message }).call
    puts "Demonstração criada em #{(Time.current - started).round} s."
  end

  desc "Apaga e recria a demonstração (só com CRM_DEMO=1); roda todo dia às 4h pelo Sidekiq"
  task demo_reset: :environment do
    run = Demo::Reset.new.call(log: ->(message) { puts message })
    puts "Demonstração recriada: #{run.note}."
  rescue Demo::Reset::Refused => error
    abort "Recusado: #{error.message}"
  end
end
