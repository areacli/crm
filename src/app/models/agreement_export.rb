# Uma exportação do arquivo de acordos (11, R244): quem, quando, a forma (novidades desde a última exportação manual, completo ou as novidades do dia), quantas linhas.
# O arquivo fica em `storage/agreement_exports` por 30 dias e depois é apagado; a exportação pode ser refeita a qualquer momento a partir dos dados do dia.
class AgreementExport < ApplicationRecord
  include TenantScoped

  FORMS = %w[news full daily].freeze
  KEEP_DAYS = 30
  DIRECTORY = Rails.root.join("storage", "agreement_exports")

  belongs_to :user, optional: true

  enum :form, FORMS.index_with(&:itself), prefix: :form, validate: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :manual, -> { where(form: %w[news full]) }

  def path = file_name.present? ? DIRECTORY.join(file_name) : nil

  def default_file_name = "acordos-#{tenant_id}-#{id}-#{form}.csv"

  def path_for_write = DIRECTORY.join(default_file_name)

  def available? = path.present? && File.exist?(path) && created_at > KEEP_DAYS.days.ago

  # Apaga os arquivos com mais de 30 dias (a exportação segue registrada).
  def self.purge!
    where(created_at: ...KEEP_DAYS.days.ago).where.not(file_name: nil).find_each do |export|
      FileUtils.rm_f(export.path)
      export.update_columns(file_name: nil)
    end
  end
end
