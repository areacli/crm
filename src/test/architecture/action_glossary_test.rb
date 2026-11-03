require "test_helper"

# Glossário de ações (padrões de interface, P16, revisão 20): um verbo por ação, em todas as telas. O teste lê os rótulos dos botões (button_to,
# painel, confirmação, envio do formulário de painel, links com cara de botão e <button>) e falha com verbo fora da lista. "Mudar", "Alterar",
# "Apagar", "Tirar", "Novo", "Cadastrar", "Subir", "Descer" e "Corrigir" saíram: a mesma ação tem um nome só (Editar, Excluir, Criar, Mover).
# Filas (15; padrões de interface, revisão 29): "Próximo" (pedir a próxima entrega), "Devolver" (a entrega volta à fila) e "Liberar" (o gestor
# encerra a entrega de um operador) entram no glossário com o sentido da especificação. Meios de pagamento (16; revisão 31): "Emitir" (criar um
# instrumento de pagamento) e "Reemitir" (cancelar o vigente e emitir outro).
class ActionGlossaryTest < ActiveSupport::TestCase
  VERBS = %w[
    Abrir Alocar Anonimizar Anular Aprovar Ativar Baixar Buscar Calcular Cancelar Concluir Conferir Confirmar Continuar Credenciar Criar Decidir
    Desativar Descartar Desfazer Desistir Desmarcar Devolver Distribuir Duplicar Editar Emitir Entrar Enviar Estornar Excluir Exportar Filtrar Gerar Importar Incluir
    Liberar Marcar Mostrar Esconder Mover Próximo Quebrar Reativar Recolher Recusar Redefinir Reemitir Registrar Reter Reverter Sair Salvar Simular Testar Transferir Tratar Trocar Usar Ver Voltar
  ].freeze
  RETIRED = %w[Mudar Alterar Apagar Tirar Novo Nova Cadastrar Subir Descer Remover Acrescentar Corrigir Dar].freeze
  # A página do design system mostra as variantes de botão pelo nome (Primário, Secundário...).
  EXEMPT = %w[app/views/design_system/show.html.erb].freeze

  def labels
    Rails.root.glob("{app/views/**/*.erb,app/helpers/**/*.rb}").reject { |file| EXEMPT.any? { file.to_s.end_with?(_1) } }.flat_map do |file|
      source = File.read(file)
      found = source.scan(/(?:button_to|abrir_painel|confirmar_no_painel)\s*\(?\s*\(?(?:[^"(\n]*\?\s*)?"([^"#]+)"/).flatten
      found += source.scan(/\?\s*"([^"#]+)"\s*:\s*"([^"#]+)"\)\s*,\s*(?:titulo|edit_|new_)/).flatten
      found += source.scan(/(?:enviar|acao):\s*"([^"#]+)"/).flatten
      found += source.scan(/link_to\s*\(?\s*"([^"#]+)"[^\n]*class:\s*"botao/).flatten
      found += source.scan(/<button[^>]*>\s*([[:upper:]][[:alpha:]]+[^<{"]*?)\s*</).flatten
      found.map { |label| [ label, file.relative_path_from(Rails.root).to_s ] }
    end
  end

  test "todo botão começa por um verbo do glossário" do
    outside = labels.reject { |label, _| VERBS.include?(label.split.first) }
    assert_empty outside.uniq, "rótulos fora do glossário (P16): #{outside.uniq.map { |label, file| "#{label} (#{file})" }.join('; ')}"
  end

  test "os verbos retirados não aparecem em nenhum rótulo" do
    retired = labels.select { |label, _| RETIRED.include?(label.split.first) }
    assert_empty retired.uniq
  end
end
