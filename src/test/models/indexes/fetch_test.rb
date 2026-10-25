require "test_helper"

# Busca dos índices no Banco Central (08, R142 a R144, R146) com respostas gravadas: nenhum teste chama a API.
class IndexesFetchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  def jan_2024 = { 433 => [ [ "01/01/2024", "0.42" ] ], 188 => [ [ "01/01/2024", "0.57" ] ], 189 => [ [ "01/01/2024", "0.07" ] ], 4390 => [ [ "01/01/2024", "0.97" ] ] }

  def value(series, month) = IndexRate.find_by(series: series, month: month)&.value

  test "R142 (critério de aceite): a primeira busca grava os quatro valores de jan/2024 com origem e data, e registra a execução" do
    fake_bank(jan_2024)
    travel_to Date.new(2026, 10, 21) do
      run = Indexes::Fetch.new.call
      assert run.succeeded?
      assert_equal 4, run.processed
    end
    assert_equal [ 0.42, 0.57, 0.07, 0.97 ].map { |v| BigDecimal(v.to_s) }, %w[ipca inpc igpm selic].map { |s| value(s, Date.new(2024, 1, 1)) }
    assert IndexRate.all.all? { |rate| rate.fetched_at.present? && !rate.partial }
    assert_equal 1, TaskRun.where(tenant_id: nil, name: "index_fetch").count
  end

  test "R142: sem mês trazido a busca vai desde janeiro de 2000; depois, os últimos 3 meses" do
    client = fake_bank(jan_2024)
    travel_to Date.new(2026, 10, 21) do
      Indexes::Fetch.new.call
      Indexes::Fetch.new.call
    end
    assert_equal Date.new(2000, 1, 1), client.calls.first[1]
    assert_equal Date.new(2023, 11, 1), client.calls.last[1], "desde dois meses antes do último mês trazido (jan/2024), ou 3 meses atrás, o que vier antes"
  end

  test "R143 (critério de aceite): a Selic de outubro em 20/10 fica parcial; em 01/11 vira mês fechado" do
    fake_bank(4390 => [ [ "01/10/2026", "0.61" ] ])
    travel_to(Date.new(2026, 10, 20)) { Indexes::Fetch.new.call }
    selic = IndexRate.find_by!(series: "selic", month: Date.new(2026, 10, 1))
    assert selic.partial
    assert_equal BigDecimal("0.61"), selic.value

    fake_bank(4390 => [ [ "01/10/2026", "0.64" ] ])
    travel_to(Date.new(2026, 11, 1)) { Indexes::Fetch.new.call }
    selic.reload
    assert_not selic.partial
    assert_equal BigDecimal("0.64"), selic.value
  end

  test "R144 (critério de aceite): Banco Central fora do ar não apaga nada, registra a falha e levanta para tentar de novo" do
    fake_bank(jan_2024)
    Indexes::Fetch.new.call
    fake_bank(433 => Indexes::SourceError.new("o Banco Central não respondeu"), 188 => [], 189 => [], 4390 => [])
    error = assert_raises(Indexes::Fetch::Failed) { Indexes::Fetch.new.call }
    assert_match(/IPCA: o Banco Central não respondeu/, error.message)

    run = TaskRun.where(tenant_id: nil, name: "index_fetch").order(:id).last
    assert run.failed?
    assert_equal 4, IndexRate.count, "nada foi apagado"
    assert_equal 1, TaskRun.where(tenant_id: nil, name: "index_fetch", status: "succeeded").count
  end

  test "caso de exceção: texto no lugar de número ou mês repetido descarta a série inteira, e as outras seguem" do
    fake_bank(433 => [ [ "01/01/2024", "abc" ] ], 188 => [ [ "01/01/2024", "0.5" ], [ "01/01/2024", "0.6" ] ], 189 => [ [ "01/01/2024", "0.07" ] ], 4390 => [ [ "01/01/2024", "0.97" ] ])
    assert_raises(Indexes::Fetch::Failed) { Indexes::Fetch.new.call }
    assert_equal %w[igpm selic], IndexRate.order(:series).pluck(:series)
    run = TaskRun.where(name: "index_fetch").last
    assert_match(/IPCA: resposta inválida/, run.note)
    assert_match(/INPC: resposta inválida/, run.note)
  end

  test "caso de exceção: valor revisado pelo Banco Central é gravado e contado como revisado" do
    fake_bank(433 => [ [ "01/09/2026", "1.57" ] ])
    travel_to(Date.new(2026, 10, 21)) { Indexes::Fetch.new.call }
    fake_bank(433 => [ [ "01/09/2026", "1.52" ] ])
    run = travel_to(Date.new(2026, 10, 22)) { Indexes::Fetch.new.call }
    assert_equal BigDecimal("1.52"), value("ipca", Date.new(2026, 9, 1))
    assert_match(/0 meses novos e 1 revisados/, run.note)
  end

  test "R147: uma busca de cada vez; com uma em andamento a outra é adiada" do
    fake_bank(jan_2024)
    TaskRun.create!(name: "index_fetch", started_at: 1.minute.ago)
    run = Indexes::Fetch.new.call
    assert run.skipped?
    assert_equal 0, IndexRate.count
  end

  test "o job tenta de novo a cada 5 minutos, 3 vezes, e termina sem repetir" do
    fake_bank(433 => Indexes::SourceError.new("o Banco Central não respondeu"), 188 => [], 189 => [], 4390 => [])
    perform_enqueued_jobs { FetchIndexesJob.perform_later } rescue flunk("a falha não deve sair do job depois das tentativas")
    assert_equal 3, TaskRun.where(name: "index_fetch", status: "failed").count
  end

  test "a busca transmite indexes-changed" do
    fake_bank(jan_2024)
    assert_broadcasts(IndexesChannel.broadcasting_for("all"), 1) { Indexes::Fetch.new.call }
  end

  test "o cliente real lê o formato do SGS e recusa erro de HTTP e falta de resposta" do
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.instance_variable_set(:@read, true)
    ok.instance_variable_set(:@body, '[{"data":"01/09/2026","valor":"-0.32"}]')
    http = Struct.new(:response) { def start(*, **) = yield(self); def get(*) = response }
    range = { from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30) }
    assert_equal [ { "data" => "01/09/2026", "valor" => "-0.32" } ], Indexes::BcbClient.new(http: http.new(ok)).series(433, **range)

    failing = Net::HTTPInternalServerError.new("1.1", "500", "Erro")
    assert_raises(Indexes::SourceError) { Indexes::BcbClient.new(http: http.new(failing)).series(433, **range) }
    silent = Class.new { def start(*, **) = raise(Timeout::Error) }
    assert_raises(Indexes::SourceError) { Indexes::BcbClient.new(http: silent.new).series(433, **range) }
  end
end
