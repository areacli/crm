# Uma carga de arquivo, com conferência e confirmação (R10). Cada mudança de situação, e o andamento a cada cinco pontos, vai ao
# navegador por evento do Action Cable (decisão 0020: sem polling).
class Import < ApplicationRecord
  include TenantScoped

  PROGRESS_STEP = 5

  belongs_to :user, optional: true
  belongs_to :confirmed_by, class_name: "User", optional: true
  has_many :rejections, class_name: "ImportRejection", dependent: :delete_all

  enum :status, { received: "received", checking: "checking", checked: "checked", confirming: "confirming", confirmed: "confirmed",
                  discarded: "discarded", rejected: "rejected", failed: "failed" }, validate: true
  # Carteira, pagamentos ou estornos: o tipo decide a planilha, a conferência, a confirmação e as permissões (2 e 3, ou 5 e 6).
  enum :kind, { portfolio: "portfolio", payments: "payments", reversals: "reversals" }, validate: true
  enum :mode, { incremental: "incremental", full_sync: "full_sync" }, validate: true

  # Situações em que a importação ocupa o credor (uma por vez, R10): garantido pelo índice parcial do banco.
  IN_PROGRESS = %w[received checking checked confirming].freeze

  scope :in_progress, -> { where(status: IN_PROGRESS) }
  scope :recent, -> { order(id: :desc) }

  after_commit :announce_change, on: %i[create update]

  # Caminho do arquivo guardado (relativo a storage/), enquanto a importação o precisa.
  def file_path = Rails.root.join("storage", stored_path.to_s)

  def payments_kind? = payments? || reversals?

  # O conferidor e o confirmador do tipo da importação.
  def checker = payments_kind? ? Payments::ImportChecker.new : Portfolio::ImportChecker.new

  def confirmer = payments_kind? ? Payments::ImportConfirmer.new : Portfolio::ImportConfirmer.new

  def in_progress? = IN_PROGRESS.include?(status)

  # Em andamento de verdade, isto é, esperando o sistema (não esperando a confirmação do gestor).
  def working? = in_progress? && !checked?

  def summary_data = (summary || {}).with_indifferent_access

  private
    def announce_change
      return unless previous_changes.key?("status") || previous_changes.key?("id") || progress_advanced?

      Rails.cache.write("import-broadcast:#{id}", progress_percent, expires_in: 1.hour)
      ImportsChannel.broadcast_to(tenant, { event: "import-changed", import_id: id, status: status, progress_percent: progress_percent })
    end

    def progress_advanced?
      return false unless previous_changes.key?("progress_percent")

      last = Rails.cache.read("import-broadcast:#{id}")
      last.nil? || (progress_percent - last).abs >= PROGRESS_STEP
    end
end
