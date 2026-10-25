module Agreements
  # O aviso da lista de exportações (11, R244, AB8): entrada, título de estorno ou título reaberto com vencimento nos próximos 3 dias úteis que não está em nenhum arquivo baixado
  # (manual ou do dia).
  module UnseenEntries
    Entry = Data.define(:tenant, :agreement, :bill)

    module_function

    def for(tenants, today: Date.current)
      limit = BusinessDaysAhead.call(today, 3)
      tenants.flat_map do |tenant|
        downloaded_at = AgreementExport.where(tenant_id: tenant.id).where.not(downloaded_at: nil).minimum(:downloaded_at)
        entries = Bill.where(tenant_id: tenant.id, kind: "agreement", status: %w[scheduled active]).where(due_date: today..limit).includes(:agreement).filter_map do |bill|
          next unless bill.composition["number"].to_i.zero?
          next if downloaded_at && downloaded_at > bill.created_at

          Entry.new(tenant, bill.agreement, bill)
        end
        # R244, R233: o título de estorno novo e o título de acordo reaberto por estorno também avisam, quando vencem nos próximos 3 dias úteis e nenhum arquivo baixado os levou.
        extra = Bill.where(tenant_id: tenant.id, status: "active").where(due_date: today..limit).where("kind = 'reversal' or (kind = 'agreement' and jsonb_exists(composition, 'reopened_on'))").includes(:agreement, :origin_agreement)
        entries + extra.filter_map do |bill|
          next if downloaded_at && downloaded_at > bill.updated_at

          Entry.new(tenant, bill.agreement || bill.origin_agreement, bill)
        end
      end
    end

    module BusinessDaysAhead
      module_function

      def call(from, count)
        date = from
        count.times { date = Charges::BusinessDays.next_business(date + 1) }
        date
      end
    end
  end
end
