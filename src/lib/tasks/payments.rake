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

    # 12, revisão 5, R284t: o SDK de navegador do PagBank não declara licença e fica fora do repositório público (plano, PB6). Esta tarefa o baixa do endereço
    # do PagBank e só o grava se o SHA-256 for o do adaptador: arquivo novo no PagBank é uma troca consciente (SHA-256 novo, teste, homologação).
    desc "Baixa o SDK de navegador do fornecedor e confere o SHA-256 do adaptador: crm:payments:card_sdk[pagbank]"
    task :card_sdk, %i[provider] => :environment do |_task, args|
      adapter = Payments::Providers.adapter(args.fetch(:provider))
      source, sha, file = adapter.class::SDK_SOURCE, adapter.class::SDK_SHA256, adapter.class::SDK_FILE
      response = Payments::Providers::HttpClient.new.request(:get, source, max_bytes: 2.megabytes)
      abort "Download recusado (HTTP #{response.status})." unless response.status == 200
      found = Digest::SHA256.hexdigest(response.body.b)
      abort "O arquivo publicado mudou: SHA-256 #{found}, o adaptador espera #{sha}. Leia, teste e troque o SHA-256 no adaptador antes de usar." unless found == sha

      path = Rails.root.join("vendor/javascript", file)
      File.binwrite(path, response.body.b)
      puts "#{path} gravado (SHA-256 #{found})."
    end

    desc "Roda a conciliação de um credor agora: crm:payments:reconcile[id_do_credor]"
    task :reconcile, %i[tenant_id] => :environment do |_task, args|
      run = Payments::Reconciler.new(Tenant.find(args.fetch(:tenant_id))).call
      puts "#{run.status}: #{run.note}"
    end
  end
end
