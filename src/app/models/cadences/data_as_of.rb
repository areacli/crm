module Cadences
  # Até quando os dados estavam (21, R435, Q7): a última carga de carteira e de pagamentos confirmadas, e a última lista de pagos de cada integração.
  module DataAsOf
    module_function

    def for(tenant)
      imports = Import.where(tenant_id: tenant.id, status: "confirmed").group(:kind).maximum(:finished_at)
      lists = tenant.payment_accounts.active.where.not(paid_listed_until: nil).pluck(:nickname, :paid_listed_until)
      { "portfolio" => imports["portfolio"]&.iso8601, "payments" => imports["payments"]&.iso8601,
        "paid_lists" => lists.to_h { |name, at| [ name, at.iso8601 ] } }
    end
  end
end
