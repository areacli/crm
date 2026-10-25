require "test_helper"

# Quando o valor atualizado é recalculado (09, R173): todo dia depois dos segmentos, depois de carga, pagamentos, estornos, correção de índice,
# mudança de encargos e busca manual; sempre por credor.
class ValuesJobsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  test "o recálculo dos segmentos é seguido pelo dos valores atualizados do mesmo credor" do
    assert_enqueued_with(job: ValuesRecalculationJob) { SegmentsRecalculationJob.perform_now(@alfa) }
    assert_equal [ @alfa ], enqueued_jobs.select { |job| job["job_class"] == "ValuesRecalculationJob" }.map { |job| GlobalID::Locator.locate(job["arguments"].first["_aj_globalid"]) }
  end

  test "R173: a correção de um índice do credor recalcula só o credor que corrigiu" do
    seed_indexes!
    Indexes::Adjuster.new(users(:joana), @alfa).correct(series: "ipca", month: "2026-09", value: "1,0", reason: "teste")
    jobs = enqueued_jobs.select { |job| job["job_class"] == "ValuesRecalculationJob" }
    assert_equal 1, jobs.size
    assert_equal "gid://crm/Tenant/#{@alfa.id}", jobs.first["arguments"].first["_aj_globalid"]
  end

  test "R173: a busca manual dos índices recalcula todos os credores ativos; a diária não (o recálculo dos segmentos já a segue)" do
    fake_bank({})
    FetchIndexesJob.perform_now
    assert_no_enqueued_jobs(only: ValuesDispatchJob)
    FetchIndexesJob.perform_now(true)
    assert_enqueued_jobs 1, only: ValuesDispatchJob
    ValuesDispatchJob.perform_now
    assert_equal Tenant.where(active: true).count, enqueued_jobs.count { |job| job["job_class"] == "ValuesRecalculationJob" }
  end

  test "o agendamento diário continua o dos segmentos, que encadeia o dos valores" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    assert_equal "SegmentsDispatchJob", schedule.dig("segments_recalculation", "class")
  end
end
