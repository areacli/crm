namespace :crm do
  namespace :payments do
    desc "Registra no fornecedor o webhook do Pix da conta (12, parte D): crm:payments:register_pix_webhook[id_da_conta]"
    task :register_pix_webhook, %i[account_id] => :environment do |_task, args|
      account = PaymentAccount.find(args.fetch(:account_id))
      abort "A conta não é de Pix, ou o fornecedor não registra webhook por aqui." unless account.modality == "pix" && account.adapter.respond_to?(:register_pix_webhook)

      account.adapter.register_pix_webhook(account)
      puts "Webhook do Pix registrado para a conta #{account.id}."
    rescue Payments::Providers::Error => error
      abort "Não foi possível registrar: #{error.message}"
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
