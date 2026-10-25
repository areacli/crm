# Evento do acordo (11, R244): montagem, aprovação, recusa, aceite, cancelamento, expiração. Só inserção; é a fonte do histórico da ficha e do arquivo de acordos.
class AgreementEvent < ApplicationRecord
  KINDS = %w[built approved refused accepted canceled replaced expired not_approved effectuated settled broken reactivated settlement_calculated
             reversal_title reversion_opened reversion_desisted reverted reversal_waiting reversal_decided credit_used renegotiated reopened].freeze

  belongs_to :tenant
  belongs_to :agreement
  belongs_to :user, optional: true

  def self.log!(agreement, kind, user: nil, data: {})
    create!(tenant_id: agreement.tenant_id, agreement: agreement, user: user, kind: kind, data: data, occurred_at: Time.current)
  end
end
