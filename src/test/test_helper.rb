ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/csv_helper"
require_relative "support/payments_helper"
require_relative "support/contacts_helper"
require_relative "support/discrepancies_helper"
require_relative "support/registry_test_helper"
require_relative "support/titular_helper"
require_relative "support/segments_test_helper"
require_relative "support/charges_test_helper"
require_relative "support/promises_test_helper"
require_relative "support/agreements_test_helper"
require_relative "support/payment_accounts_helper"
require_relative "support/efi_http_helper"
require_relative "support/checkouts_helper"
require_relative "support/webhooks_helper"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include CsvHelper
    include PaymentsHelper
    include ContactsHelper
    include DiscrepanciesHelper
    include RegistryTestHelper
    include TitularHelper
    include SegmentsTestHelper
    include ChargesTestHelper
    include PromisesTestHelper
    include AgreementsTestHelper
    include PaymentAccountsHelper
    include EfiHttpHelper
    include CheckoutsHelper
    include WebhooksHelper

    # Nenhum teste chama a Efí real (12): o cliente padrão recusa; os testes da Efí trocam por um falso com respostas gravadas. O token fica só na memória do processo.
    setup do
      Payments::Providers::Efi.http_client = EfiHttpHelper::Blocked.new
      Payments::Providers::Efi::TokenStore.reset!
      Payments::Providers::Fake.reset!
    end

    # O limite de entradas por IP (`rate_limit`) conta no cache em memória do processo: cada teste começa sem a contagem dos outros.
    setup { Rails.cache.clear }
  end
end
