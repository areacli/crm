# Página de referência do design system (o documento do design system do projeto, seção 10): só em desenvolvimento e teste (ver config/routes.rb).
class DesignSystemController < ApplicationController
  allow_unauthenticated_access if respond_to?(:allow_unauthenticated_access)

  CORES = %w[marinho azul azul-escuro amarelo laranja texto texto-suave superficie linha linha-forte perigo sucesso atencao].freeze

  def show
    @cores = CORES
    @menu = [ { titulo: "Carteira", itens: [ { rotulo: "Resumo", caminho: root_path }, { rotulo: "Clientes", caminho: design_system_path, atual: true } ] },
              { titulo: "Administração", itens: [ { rotulo: "Configuração", caminho: root_path } ] } ]
  end
end
