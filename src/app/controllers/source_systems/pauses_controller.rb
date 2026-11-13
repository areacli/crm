module SourceSystems
  # Pausar (R398: o sistema pausado recusa importação nova, e a que está em andamento termina) e reativar um sistema.
  class PausesController < ApplicationController
    before_action :set_system

    def create = change(:pause)

    def destroy = change(:resume)

    private
      def set_system
        @system = SourceSystem.find(params[:source_system_id])
        authorize @system, :update?
      end

      def change(action)
        Manager.new(Current.user).public_send(action, @system)
        panel_finish(source_systems_path, notice: t("source_systems.pauses.#{action == :pause ? 'create' : 'destroy'}.done", name: @system.name), atualizar: true)
      rescue Manager::Refused => error
        panel_refuse(source_systems_path, error.message)
      end
  end
end
