# Rotação das chaves de cifragem em lote (12, R255), para rodar na fila quando o administrador não quiser prender o console.
class RotateEncryptionJob < ApplicationJob
  queue_as :default

  def perform = KeyRotation.new.call
end
