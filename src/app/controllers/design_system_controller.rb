# Página de referência do design system (o documento do design system do projeto, seção 10): só em desenvolvimento e teste (ver config/routes.rb).
class DesignSystemController < ApplicationController
  allow_unauthenticated_access if respond_to?(:allow_unauthenticated_access)

  CORES = %w[marinho azul azul-escuro amarelo laranja texto texto-suave superficie linha linha-forte perigo sucesso atencao].freeze

  # Exemplos da página de referência na SPA (só em desenvolvimento e teste): respostas de mentira para mostrar os estados da espera.
  def calculo
    sleep params[:demora].to_f.clamp(0, 6)
    return head(:internal_server_error) if params[:falhar].present?

    a, b = params.values_at(:a, :b)
    @situacao = if a.blank? || b.blank? then :incompleto elsif a.to_f.negative? || b.to_f.negative? then :recusado end
    @soma = a.to_f + b.to_f
    render partial: "design_system/calculo"
  end

  def inline
    nome = params[:nome].to_s.strip
    return inline_refuse("Informe o nome.") if nome.empty?

    inline_finish(nome)
  end

  def lento
    sleep params[:segundos].to_f.clamp(0, 6)
    head(:internal_server_error) if params[:falhar].present?
  end

  def janela
  end

  def dialogo
  end

  def gravar_dialogo
    sleep params.dig(:exemplo, :demora).to_f.clamp(0, 6)
    @nota = params.dig(:exemplo, :nota).to_s.strip
    return panel_finish(design_system_path, notice: "Nota salva.") if @nota.present?

    @erro = "Escreva a nota."
    render :dialogo, status: :unprocessable_content
  end

  def show
    @cores = CORES
    @menu = [ { titulo: "Carteira", itens: [ { rotulo: "Resumo", caminho: root_path }, { rotulo: "Clientes", caminho: design_system_path, atual: true } ] },
              { titulo: "Administração", itens: [ { rotulo: "Configuração", caminho: root_path } ] } ]
  end
end
