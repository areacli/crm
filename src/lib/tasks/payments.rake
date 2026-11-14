namespace :crm do
  namespace :payments do
    desc "Cadastra no fornecedor o endereço do webhook da integração (12, revisão 4, R284g): crm:payments:register_webhook[id_da_integração]"
    task :register_webhook, %i[account_id] => :environment do |_task, args|
      account = PaymentAccount.find(args.fetch(:account_id))
      url = Payments::WebhookRegistration.new(account).call
      puts "Webhook cadastrado para a integração #{account.id}: #{url.sub(/hmac=\h+/, 'hmac=…')}"
    rescue Payments::Providers::Error => error
      abort "Não foi possível cadastrar: #{error.message}"
    end

    desc "Reprocessa os avisos de pagamento que falharam ou ficaram parados: crm:payments:reprocess_events[id_do_credor]"
    task :reprocess_events, %i[tenant_id] => :environment do |_task, args|
      count = Payments::EventReprocessor.new(Tenant.find(args.fetch(:tenant_id))).call
      puts "#{count} aviso(s) enfileirado(s) de novo."
    end

    desc "Roda a conciliação de um credor agora: crm:payments:reconcile[id_do_credor]"
    task :reconcile, %i[tenant_id] => :environment do |_task, args|
      run = Payments::Reconciler.new(Tenant.find(args.fetch(:tenant_id))).call
      puts "#{run.status}: #{run.note}"
    end
  end
end
