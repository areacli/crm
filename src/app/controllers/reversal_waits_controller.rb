# Estornos à espera do gestor (11, R233, AH2, AJ1): a lista dos credores em que a pessoa tem "administrar acordos", com há quanto tempo cada um espera, e a decisão com motivo. A opção
# que o estado atual não permite não aparece. A lista se refaz por evento do WebSocket, sem polling.
class ReversalWaitsController < ApplicationController
  def index
    authorize ReversalWait
    @waits = policy_scope(ReversalWait).waiting.oldest_first.includes(:tenant, :contract, payment: :channel, agreement: :customer).to_a
    @decided = policy_scope(ReversalWait).where(state: "decided").order(decided_at: :desc).limit(20).includes(:tenant, :decided_by, agreement: :customer).to_a
    @options = @waits.to_h { |wait| [ wait.id, Agreements::WaitDecision.new(Current.user).options(wait) ] }
    @cable = Current.user.tenant_ids_with("administer_agreements").map { |id| { channel: "AgreementsChannel", tenant_id: id } }.to_json
    render partial: "reversal_waits/result" if htmx_fragment?
  end

  # A decisão (opção e motivo) se pede num modal pequeno.
  def edit
    @wait = policy_scope(ReversalWait).includes(:payment, :agreement).find(params[:id])
    authorize @wait, :decide?
    @choices = Agreements::WaitDecision.new(Current.user).options(@wait)
  end

  def update
    @wait = policy_scope(ReversalWait).includes(:payment, :agreement).find(params[:id])
    authorize @wait, :decide?
    raw = params.expect(decision: %i[choice note])
    Agreements::WaitDecision.new(Current.user).decide!(@wait, raw[:choice].to_s, raw[:note])
    panel_finish(reversal_waits_path, notice: t(".done"), atualizar: true, eventos: %w[cable:agreements-changed])
  rescue Agreements::Refused => error
    @choices = Agreements::WaitDecision.new(Current.user).options(@wait)
    panel_error(error.message, reversal_waits_path, :edit)
  end
end
