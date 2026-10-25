require "test_helper"

# Aviso de certificado a vencer (12, R264): uma vez, 30 dias antes, no sino de quem tem a permissão 14 no credor.
class CertificateWatchTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "p@a.com" })
    @account.assign_values(files: { "certificate" => p12_upload(days: 20) })
    @account.save!
    @manager = users(:joana)
    @operator = users(:carlos)
  end

  test "com 31 dias antes nada, aos 30 o aviso nasce para o gestor e não para o operador, e não repete (R264)" do
    today = Date.current - 1
    assert_equal 0, Payments::CertificateWatch.new.call(today: Date.current - 11), "faltam 31 dias"
    assert_equal 1, Payments::CertificateWatch.new.call(today: Date.current - 10), "faltam 30 dias"
    notice = Notice.where(user: @manager, kind: "certificate_expiring").last
    assert_equal [ @account.nickname, @alfa.name ], [ notice.data["account"], notice.data["tenant_name"] ]
    assert_equal (Date.current + 20).strftime("%d/%m/%Y"), notice.data["expires_on"]
    assert_equal 0, Notice.where(user: @operator, kind: "certificate_expiring").count
    assert_equal 0, Payments::CertificateWatch.new.call(today: today)
    assert_equal 1, Notice.where(user: @manager, kind: "certificate_expiring").count
  end

  test "trocar o certificado volta a avisar quando o novo estiver perto de vencer (R264)" do
    Payments::CertificateWatch.new.call(today: Date.current)
    @account.assign_values(files: { "certificate" => p12_upload(days: 15) })
    @account.save!
    assert_equal 1, Payments::CertificateWatch.new.call(today: Date.current)
    assert_equal 2, Notice.where(user: @manager, kind: "certificate_expiring").count
  end

  test "conta desativada e certificado longe não avisam; o aviso aparece no texto do sino (R264)" do
    other = make_account(@alfa, modality: "pix", environment: "production", nickname: "Longe", config: { "connection_result" => "ok", "pix_key" => "p@a.com" })
    other.assign_values(files: { "certificate" => p12_upload(days: 300) })
    other.save!
    @account.update!(active: false)
    assert_equal 0, Payments::CertificateWatch.new.call(today: Date.current)
  end

  test "o job diário roda o aviso (R264)" do
    assert_difference -> { Notice.where(kind: "certificate_expiring").count }, 1 do
      PaymentAccountsDailyJob.perform_now
    end
  end

  test "a tarefa está no agendamento diário" do
    entry = YAML.load_file(Rails.root.join("config/schedule.yml")).fetch("payment_accounts_daily")
    assert_equal "PaymentAccountsDailyJob", entry["class"]
    assert_equal "0 7 * * *", entry["cron"]
  end
end
