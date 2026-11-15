# Peças da mensageria (21, R446): nome, canal e ativa, no lugar do dono até a mensageria existir; o conteúdo vem com ela. A peça usada numa régua
# não se apaga, só se desativa, e a lista mostra em quais réguas ela é usada. Permissão 24.
module Settings
  class MessagePiecesController < ApplicationController
    before_action :set_tenant
    before_action :set_piece, only: %i[edit update]

    def index
      @pieces = MessagePiece.where(tenant: @tenant).order(:channel, :name).to_a
    end

    def new
      @piece = MessagePiece.new(tenant: @tenant, channel: "sms", active: true)
    end

    def create
      @piece = MessagePiece.new(piece_params.merge(tenant: @tenant))
      @piece.save!
      Change.record!(@piece, "created", tenant_id: @tenant.id, actor: Current.user, field: "name", after: @piece.name)
      panel_finish(settings_message_pieces_path(credor: @tenant.id), notice: t(".done", name: @piece.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_content
    end

    def edit
    end

    def update
      before = @piece.attributes.slice("name", "active")
      @piece.update!(piece_params.except(:channel))
      before.each { |field, value| Change.record!(@piece, "updated", tenant_id: @tenant.id, actor: Current.user, field: field, before: value.to_s, after: @piece[field].to_s) if @piece[field] != value }
      panel_finish(settings_message_pieces_path(credor: @tenant.id), notice: t(".done", name: @piece.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    private
      def set_tenant
        @tenants = Tenant.where(id: Current.user.tenant_ids_with(MessagePiecePolicy::KEY)).order(:name)
        @tenant = @tenants.find_by(id: params[:credor]) || @tenants.first or raise Pundit::NotAuthorizedError
        authorize MessagePiece.new(tenant: @tenant), :create?
      end

      def set_piece = @piece = MessagePiece.find_by!(id: params[:id], tenant_id: @tenant.id)

      def piece_params
        attributes = params.expect(message_piece: %i[name channel active])
        attributes[:active] = attributes[:active] == "1" if attributes.key?(:active)
        attributes
      end
  end
end
