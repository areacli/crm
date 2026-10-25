# Importações. Cada tipo tem as suas permissões, sempre no credor da importação (MT-3): carteira, enviar (2) e confirmar (3); pagamentos
# e estornos, enviar e conferir (5) e confirmar (6).
class ImportPolicy < ApplicationPolicy
  UPLOAD = { "portfolio" => "upload_imports", "payments" => "upload_payments", "reversals" => "upload_payments" }.freeze
  CONFIRM = { "portfolio" => "confirm_imports", "payments" => "confirm_payments", "reversals" => "confirm_payments" }.freeze

  def index? = (UPLOAD.values + CONFIRM.values).uniq.any? { |permission| user.permitted_anywhere?(permission) }
  def show? = permitted?(UPLOAD.fetch(record.kind)) || permitted?(CONFIRM.fetch(record.kind))
  # `new?` vale para a classe (menu) e para uma importação do tipo pedido.
  def new? = record.is_a?(Class) ? UPLOAD.values.uniq.any? { |permission| user.permitted_anywhere?(permission) } : user.permitted_anywhere?(UPLOAD.fetch(record.kind))
  def create? = permitted?(UPLOAD.fetch(record.kind))
  # Confirmar ou descartar: só uma importação conferida, por quem tem a permissão de confirmar do tipo dela no credor.
  def confirm? = record.checked? && permitted?(CONFIRM.fetch(record.kind))
  def discard? = confirm?

  # Acompanhar as importações do credor (a tela e o canal do WebSocket): qualquer permissão de importação nele.
  def watch? = (UPLOAD.values + CONFIRM.values).uniq.any? { |permission| permitted?(permission) }

  class Scope < Scope
    # Cada tipo aparece para quem tem a permissão de enviar ou de confirmar o tipo no credor.
    def resolve
      conditions = UPLOAD.keys.filter_map do |kind|
        ids = (user.tenant_ids_with(UPLOAD.fetch(kind)) + user.tenant_ids_with(CONFIRM.fetch(kind))).uniq
        ActiveRecord::Base.sanitize_sql_array([ "(imports.kind = ? and imports.tenant_id in (?))", kind, ids ]) if ids.any?
      end
      scope.where(conditions.any? ? conditions.join(" or ") : "false")
    end
  end
end
