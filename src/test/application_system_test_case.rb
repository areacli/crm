require "test_helper"
require "capybara/cuprite"
require_relative "support/acessibilidade"

# Testes de sistema: navegador real (Chromium da imagem, por CDP) contra a aplicação em teste, com o axe em cada tela.
Capybara.register_driver(:cuprite_crm) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1440, 900 ], browser_path: ENV["BROWSER_PATH"], process_timeout: 30, js_errors: true,
                                browser_options: { "no-sandbox" => nil })
end

# Nos testes de sistema, o servidor e o teste dividem uma conexão com o banco (a transação do teste). O papel do RLS é da conexão (decisão
# 0024): duas requisições ao mesmo tempo nela trocariam o papel uma da outra (a que termina faz RESET ROLE no meio da outra). Em produção
# cada thread tem a sua conexão; aqui o servidor atende uma requisição por vez.
Capybara.server = :puma, { Silent: true, Threads: "1:1" }

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Acessibilidade

  driven_by :cuprite_crm
end
