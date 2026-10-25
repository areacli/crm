require "test_helper"

# Tela de índices (08, R147, R157, R158): valores globais, correção do credor, "Buscar índices agora" e permissões.
class IndexesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @month = (Date.current - 2.months).beginning_of_month
    IndexRate::SERIES.each_with_index { |series, i| IndexRate.create!(series: series, month: @month, value: "0.#{i + 4}2", fetched_at: Time.current) }
    IndexRate.create!(series: "selic", month: Date.current.beginning_of_month, value: "0.61", partial: true, fetched_at: Time.current)
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "R147: mostra os meses das quatro séries, a origem, o parcial e a situação da busca" do
    TaskRun.create!(name: "index_fetch", status: "succeeded", started_at: 1.hour.ago, finished_at: 1.hour.ago, processed: 4, note: "4 meses novos e 0 revisados.")
    entrar(users(:joana))
    get settings_indexes_path
    assert_response :success
    assert_select "th", text: %w[IPCA INPC IGP-M Selic].first
    assert_select "td", text: /0,42%/
    assert_select "td", text: /0,61% \(parcial\)/
    assert_select "td small", text: /Banco Central, /
    assert_select "p", text: /Última busca com sucesso:/
    assert_select "button", "Buscar índices agora"
  end

  test "R144: a falha da busca aparece na tela com os dias sem busca com sucesso" do
    TaskRun.create!(name: "index_fetch", status: "succeeded", started_at: 3.days.ago, finished_at: 3.days.ago)
    TaskRun.create!(name: "index_fetch", status: "failed", started_at: 1.hour.ago, finished_at: 1.hour.ago, note: "IPCA: o Banco Central não respondeu")
    entrar(users(:joana))
    get settings_indexes_path
    assert_select "div", text: /Falha em .*IPCA: o Banco Central não respondeu.*Há 3 dias sem busca com sucesso/m
  end

  test "R147: Buscar índices agora enfileira a busca; com uma em andamento o botão dá lugar a 'Busca em andamento'" do
    entrar(users(:joana))
    assert_enqueued_with(job: FetchIndexesJob) { post settings_index_search_path }
    assert_redirected_to settings_indexes_path

    TaskRun.create!(name: "index_fetch", started_at: 1.minute.ago)
    get settings_indexes_path
    assert_select "button", text: "Buscar índices agora", count: 0
    assert_select "span", "Busca em andamento"
    assert_no_enqueued_jobs { post settings_index_search_path }
  end

  test "R145, R146: corrigir com motivo, ver os dois valores, desfazer; a Beta não vê a correção da Alfa" do
    entrar(users(:joana))
    post settings_index_adjustments_path, params: { tenant_id: @alfa.id, adjustment: { series: "igpm", month: @month.strftime("%m/%Y"), value: "1,52", reason: "FGV" } }
    assert_redirected_to settings_indexes_path
    get settings_indexes_path
    assert_select "h2", text: "Escola Alfa"
    assert_select "td", text: /corrigido: 1,52% · Banco Central: 0,62%/
    adjustment = IndexAdjustment.find_by!(tenant: @alfa)
    assert_equal 0, IndexAdjustment.where(tenant: @beta).count

    delete settings_index_adjustment_path(adjustment), params: { adjustment: { reason: " " } }
    assert_redirected_to settings_indexes_path
    assert IndexAdjustment.exists?(adjustment.id), "sem motivo não desfaz"
    delete settings_index_adjustment_path(adjustment), params: { adjustment: { reason: "engano" } }
    assert_not IndexAdjustment.exists?(adjustment.id)
  end

  test "R157 (critério de aceite): com a 4 e sem a 14 vê tudo sem os botões; correção direta e busca direta são recusadas e registradas" do
    reader = make_user(@alfa, %w[change_settings])
    entrar(reader)
    get settings_indexes_path
    assert_response :success
    assert_select "button", text: "Buscar índices agora", count: 0
    assert_select "summary", text: "Corrigir índice", count: 0
    assert_difference -> { AccessEvent.where(event: "access_denied", user_id: reader.id).count }, 2 do
      post settings_index_adjustments_path, params: { tenant_id: @alfa.id, adjustment: { series: "igpm", month: @month.strftime("%m/%Y"), value: "1", reason: "x" } }
      assert_response :not_found
      post settings_index_search_path
      assert_response :not_found
    end
    assert_equal 0, IndexAdjustment.count
  end

  test "R158: quem só consulta (permissão 1) abre a tela pelo endereço, sem a aba na configuração; sem permissão nenhuma, não" do
    consult = make_user(@alfa, [])
    entrar(consult)
    get settings_indexes_path
    assert_response :success
    assert_select "nav.abas a", text: "Índices", count: 0
    assert_select "button", text: "Buscar índices agora", count: 0
    delete session_path
    entrar(users(:sem_vinculo))
    get settings_indexes_path
    assert_not_equal 200, response.status
  end

  test "MT-3 e V10: a correção vale no credor do registro; quem tem a 14 só na Alfa é recusado na Beta" do
    marta = make_user(@alfa, %w[change_financial_policies])
    Membership.create!(user: marta, tenant: @beta, profile: Profile.create!(tenant: @beta, name: "Consulta", permissions: %w[view_portfolio]))
    entrar(marta)
    post settings_index_adjustments_path, params: { tenant_id: @beta.id, adjustment: { series: "igpm", month: @month.strftime("%m/%Y"), value: "1", reason: "x" } }
    assert_response :not_found
    assert AccessEvent.exists?(event: "access_denied", tenant_id: @beta.id, user_id: marta.id)
    post settings_index_adjustments_path, params: { tenant_id: @alfa.id, adjustment: { series: "igpm", month: @month.strftime("%m/%Y"), value: "1", reason: "x" } }
    assert_redirected_to settings_indexes_path
    adjustment = IndexAdjustment.find_by!(tenant: @alfa)
    other = IndexAdjustment.create!(tenant: @beta, series: "ipca", month: @month, value: "1", reason: "y", adjusted_at: Time.current)
    delete settings_index_adjustment_path(other), params: { adjustment: { reason: "x" } }
    assert_response :not_found
    assert IndexAdjustment.exists?(other.id) && IndexAdjustment.exists?(adjustment.id)
  end

  test "R142 e R144 (critério de aceite): a busca roda uma vez para o sistema todo e as duas telas mostram a mesma situação" do
    TaskRun.create!(name: "index_fetch", status: "succeeded", started_at: 1.hour.ago, finished_at: 1.hour.ago, processed: 4)
    entrar(users(:ana))
    get settings_indexes_path
    assert_select "p", text: /Última busca com sucesso/, count: 1
    assert_select "h2", text: "Escola Alfa"
    assert_select "h2", text: "Clínica Beta"
  end

  test "as abas Segmentos e Índices aparecem para quem tem a 4 ou a 14" do
    entrar(users(:joana))
    get settings_segments_path
    assert_select "nav.abas a", text: "Segmentos e encargos"
    assert_select "nav.abas a", text: "Índices"
  end
end
