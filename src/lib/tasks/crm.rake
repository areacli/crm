namespace :crm do
  desc "Verifica a plataforma: um job em cada fila do Sidekiq, cada um transmitindo um sinal no canal platform"
  task platform_check: :environment do
    PlatformCheckJob::QUEUES.each do |queue|
      PlatformCheckJob.set(queue: queue).perform_later(queue)
      puts "job enfileirado na fila #{queue}"
    end
  end
end
