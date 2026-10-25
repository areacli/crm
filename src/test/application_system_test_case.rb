require "test_helper"
require "capybara/cuprite"
require_relative "support/acessibilidade"

# Testes de sistema: navegador real (Chromium da imagem, por CDP) contra a aplicação em teste, com o axe em cada tela.
Capybara.register_driver(:cuprite_crm) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1440, 900 ], browser_path: ENV["BROWSER_PATH"], process_timeout: 30, js_errors: true,
                                browser_options: { "no-sandbox" => nil })
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Acessibilidade

  driven_by :cuprite_crm
end
