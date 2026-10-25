require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Crm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Brasília é o "hoje" do sistema (regra geral 3); instantes em timestamptz; textos de tela em pt-BR.
    config.time_zone = "Brasilia"
    config.i18n.default_locale = :"pt-BR"
    config.i18n.available_locales = [ :"pt-BR" ]

    # Filas em Valkey com Sidekiq (decisão 0020); nos testes o Active Job usa o adaptador de teste.
    config.active_job.queue_adapter = :sidekiq

    # Cifragem de atributos (guia Active Record Encryption): as chaves ficam nas credenciais cifradas de cada ambiente
    # (config/credentials/<ambiente>.yml.enc; `primary_key` é uma lista e a ÚLTIMA cifra, todas decifram). O cabeçalho do texto cifrado
    # guarda qual chave o cifrou, o que permite contar quantos registros ainda estão na chave antiga antes de retirá-la (`crm:encryption:status`).
    config.active_record.encryption.store_key_references = true

    # Active Storage no disco (12, R273). Sem rotas públicas: o arquivo só sai pelos controladores autenticados (nenhum endereço assinado é gerado).
    # Sem análise nem pré-visualização (nada de imagem do sistema), e as filas do Active Storage usam a `default` do Sidekiq.
    config.active_storage.service = :local
    config.active_storage.draw_routes = false
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.active_storage.variant_processor = :disabled
    config.active_storage.queues.analysis = :default
    config.active_storage.queues.purge = :default

    # Emissão de instrumentos em lote (12, IP-P7): pedidos por minuto ao fornecedor (os jobs do lote são espaçados por isto).
    config.x.payments.issue_per_minute = Integer(ENV.fetch("PAYMENTS_ISSUE_PER_MINUTE", 120))
    # Webhooks e conciliação (12, parte D): endereço público do CRM (para o fornecedor saber onde avisar), IPs que a Efí informa para o Pix, confiança no
    # certificado de cliente verificado pelo proxy (mTLS), dias sem conferência antes de a conciliação consultar um instrumento ativo e consultas por minuto.
    config.x.payments.public_url = ENV["CRM_PUBLIC_URL"]
    config.x.payments.webhook_ips = ENV.fetch("PAYMENTS_WEBHOOK_IPS", "34.193.116.226").split(",").map(&:strip).compact_blank
    config.x.payments.trust_mtls_header = ENV["PAYMENTS_TRUST_MTLS_HEADER"] == "1"
    config.x.payments.reconcile_after_days = Integer(ENV.fetch("PAYMENTS_RECONCILE_AFTER_DAYS", 3))
    config.x.payments.reconcile_per_minute = Integer(ENV.fetch("PAYMENTS_RECONCILE_PER_MINUTE", 120))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
