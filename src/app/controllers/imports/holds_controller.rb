# Mudanças a confirmar da conferência (17, R409a): o gestor confirma a troca de devedor ou a identidade com outro documento, item a item (`linha`)
# ou todas, e pode desfazer enquanto a importação não foi confirmada. A confirmação fica gravada na preparação; quem não a recebeu não é aplicada.
module Imports
  class HoldsController < ApplicationController
    def create
      changed = Portfolio::Holds.new(import).confirm(line)
      finish(changed.zero? ? "Nenhuma mudança a confirmar." : "#{helpers.number_br(changed)} #{changed == 1 ? 'mudança confirmada' : 'mudanças confirmadas'}. Elas entram quando a importação for confirmada.")
    end

    def destroy
      changed = Portfolio::Holds.new(import).undo(line)
      finish(changed.zero? ? "Nenhuma confirmação a desfazer." : "#{helpers.number_br(changed)} #{changed == 1 ? 'confirmação desfeita' : 'confirmações desfeitas'}.")
    end

    private
      def import
        @import ||= Import.find(params[:import_id]).tap { |import| authorize import, :confirm? }
      end

      def line = params[:linha].presence&.to_i

      def finish(notice) = panel_finish(import_path(import), notice: notice, atualizar: true)
  end
end
