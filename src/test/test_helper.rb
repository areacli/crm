ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/csv_helper"
require_relative "support/payments_helper"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include CsvHelper
    include PaymentsHelper

    # O limite de entradas por IP (`rate_limit`) conta no cache em memória do processo: cada teste começa sem a contagem dos outros.
    setup { Rails.cache.clear }
  end
end
