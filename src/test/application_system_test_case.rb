require "test_helper"
require "capybara/cuprite"
require_relative "support/acessibilidade"
require_relative "support/spa_test_helper"

# Testes de sistema: navegador real (Chromium da imagem, por CDP) contra a aplicação em teste, com o axe em cada tela.
Capybara.register_driver(:cuprite_crm) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1440, 900 ], browser_path: ENV["BROWSER_PATH"], process_timeout: 30, js_errors: true,
                                browser_options: { "no-sandbox" => nil })
end

# Nos testes de sistema, o servidor e o teste dividem uma conexão com o banco (a transação do teste). O papel do RLS é da conexão (decisão
# 0024): duas requisições ao mesmo tempo nela trocariam o papel uma da outra (a que termina faz RESET ROLE no meio da outra). Em produção
# cada thread tem a sua conexão; aqui o servidor atende uma requisição por vez.
Capybara.server = :puma, { Silent: true, Threads: "1:1" }

# O Action Cable atende o WebSocket da casca em threads próprias, fora do Puma, e também declara o papel do RLS (o `around_command` da conexão).
# Com a conexão dividida, o comando do canal trocava o papel no meio de um pedido: a lista da operação saía com tudo (o papel do dono) ou vazia (sem
# operação). Aqui o trecho com papel segura a trava da própria conexão dividida (a mesma que o Active Record segura em cada consulta e em cada transação,
# reentrante): uma trava só, sem a ordem trocada entre o pedido e o teste que travava os dois. Em produção cada thread tem a sua conexão e nada disso se
# aplica.
module ContextoExclusivoNosTestes
  def for_user(...) = ActiveRecord::Base.connection.lock.synchronize { super }
end
Operations::Context.singleton_class.prepend(ContextoExclusivoNosTestes)

# A casca da SPA carrega o EasyUI e o menu antes da primeira aba, e o servidor de teste atende um pedido por vez: 5 s de espera, no lugar dos 2 s.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Acessibilidade
  include SpaTestHelper

  driven_by :cuprite_crm
end
