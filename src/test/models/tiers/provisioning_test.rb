require "test_helper"

# Credor novo nasce com o "Demais" do enquadramento financeiro (13, R270); a agenda diária tem a busca e o recálculo (R142, R268).
class TiersProvisioningTest < ActiveSupport::TestCase
  test "Tenant.provision! cria o Demais, único e sem segmento, e nenhum segmento" do
    tenant = Tenant.provision!("Credor novo")
    demais = tenant.tiers.sole
    assert_equal [ "Demais", true, nil, "financial" ], [ demais.name, demais.catch_all, demais.segment, demais.kind ]
    assert_empty tenant.segments
    assert_raises(ActiveRecord::RecordNotUnique) { Tier.create_catch_all!(tenant) }
  end

  test "a agenda tem a busca dos índices às 5h e o recálculo dos segmentos às 5h30, depois dela" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    assert_equal [ "0 5 * * *", "FetchIndexesJob" ], schedule.fetch("fetch_indexes").values_at("cron", "class")
    assert_equal [ "30 5 * * *", "SegmentsDispatchJob" ], schedule.fetch("segments_recalculation").values_at("cron", "class")
  end

  test "o despacho enfileira um recálculo por credor ativo" do
    inactive = Tenant.provision!("Inativo").tap { |tenant| tenant.update!(active: false) }
    jobs = capture_jobs { SegmentsDispatchJob.perform_now }
    assert_equal [ tenants(:alfa), tenants(:beta) ].map(&:id).sort, jobs.map { |job| job[:args].first["_aj_globalid"].split("/").last.to_i }.sort
    assert_not_includes jobs.map { |job| job[:args].first["_aj_globalid"] }, inactive.to_global_id.to_s
  end

  private
    def capture_jobs
      ActiveJob::Base.queue_adapter = :test
      yield
      ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == SegmentsRecalculationJob }
    end
end
