# Modo de demonstração pública (CRM_DEMO=1): agenda a recriação diária. Fora do modo, nada é agendado e `crm:demo_reset` recusa.
if Rails.configuration.x.demo.enabled
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      hour, minute = Rails.configuration.x.demo.reset_at.split(":").map(&:to_i)
      Sidekiq::Cron::Job.create(name: "demo_reset", cron: "#{minute} #{hour} * * * America/Sao_Paulo", class: "DemoResetJob", queue: "default", active_job: true,
                                description: "Demonstração: apaga e recria os dados fictícios")
    end
  end
end
