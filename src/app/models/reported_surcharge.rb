# Acréscimos já aplicados pelo credor a um título (R102): guardados só para conferência; não mudam valor nem saldo. Uma linha por título,
# a da última carga que os trouxe.
class ReportedSurcharge < ApplicationRecord
  include TenantScoped

  belongs_to :bill
  belongs_to :import, optional: true
end
