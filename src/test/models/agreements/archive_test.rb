require "test_helper"

# Arquivo de acordos (11, R244): o marco das novidades e a guarda de 30 dias. Vem de test/controllers/agreement_titles_screens_test.rb.
class Agreements::ArchiveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366) ])
  end

  teardown { travel_back }

  test "R244: as novidades levam só o que aconteceu desde a última exportação manual, e o arquivo do dia não muda o marco" do
    archive = Agreements::Archive.new(@alfa)
    first = archive.export!("news", user: users(:joana))
    assert_operator first.lines, :>, 0
    second = archive.export!("news", user: users(:joana))
    assert_equal 0, second.lines, "nada de novo desde a última exportação"

    daily = archive.export!("daily", today: Date.current)
    assert_equal first.last_event_id, daily.last_event_id.then { |id| id.zero? ? first.last_event_id : id }
    assert_operator daily.lines, :>, 0, "o arquivo do dia leva o que aconteceu hoje"
    pay_lines([ pay_line("ACD-000001-01", Date.new(2026, 11, 4), 100) ])
    assert_equal second.last_event_id, AgreementExport.manual.maximum(:last_event_id)
  end

  test "R244: os arquivos duram 30 dias e depois são apagados" do
    export = Agreements::Archive.new(@alfa).export!("full", user: users(:joana))
    assert export.available?
    export.update_columns(created_at: 31.days.ago)
    AgreementExport.purge!

    assert_nil export.reload.file_name
    assert_not export.available?
  end
end
