# Importações de carteira. Enviar é a permissão 2 e confirmar ou descartar, a 3, sempre no credor da importação (MT-3).
class ImportPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("upload_imports") || user.permitted_anywhere?("confirm_imports")
  def show? = watch?
  def new? = user.permitted_anywhere?("upload_imports")
  def create? = permitted?("upload_imports")
  # Confirmar ou descartar: só uma importação conferida, por quem tem a permissão de confirmar no credor dela.
  def confirm? = record.checked? && permitted?("confirm_imports")
  def discard? = confirm?

  # Acompanhar as importações do credor (a tela e o canal do WebSocket).
  def watch? = permitted?("upload_imports") || permitted?("confirm_imports")

  class Scope < Scope
    def resolve = scope.visible_to(user, "upload_imports", "confirm_imports")
  end
end
