require "test_helper"

# Dia útil e praça (11, R249, DA36, M12): feriados nacionais calculados, estaduais e municipais importados, e a praça do cliente pelo endereço mais recente.
class Agreements::CalendarTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @sp = Municipality.create!(ibge_code: "3550308", name: "São Paulo", state: "SP")
    Municipality.create!(ibge_code: "3304557", name: "Rio de Janeiro", state: "RJ")
    Holiday.create!(state: "SP", municipality: @sp, date: Date.new(2027, 1, 25), name: "Aniversário da cidade")
    Holiday.create!(state: "SP", date: Date.new(2026, 7, 9), name: "Revolução Constitucionalista")
  end

  test "R249: os dias nacionais sem expediente (Carnaval, Corpus Christi, 31/12) e os feriados fixos e móveis" do
    calendar = Agreements::Calendar.national

    assert_not calendar.business?(Date.new(2027, 2, 8)), "segunda de Carnaval de 2027"
    assert_not calendar.business?(Date.new(2027, 2, 9)), "terça de Carnaval"
    assert calendar.business?(Date.new(2027, 2, 10)), "a Quarta-feira de Cinzas é dia útil"
    assert_not calendar.business?(Date.new(2027, 3, 26)), "Sexta-feira Santa"
    assert_not calendar.business?(Date.new(2026, 12, 31))
    assert_not calendar.business?(Date.new(2026, 11, 20)), "Consciência Negra, Lei 14.759/2023"
    assert_not calendar.business?(Date.new(2026, 12, 5)), "sábado"
  end

  test "DA36: o vencimento em dia não útil passa ao dia útil seguinte (05/12/2026, sábado, vai a 07/12)" do
    assert_equal Date.new(2026, 12, 7), Agreements::Calendar.national.next_business(Date.new(2026, 12, 5))
    assert_equal Date.new(2026, 12, 8), Agreements::Calendar.national.next_business(Date.new(2026, 12, 8))
    assert_equal Date.new(2026, 11, 3), Agreements::Calendar.national.add_business_days(Date.new(2026, 10, 30), 1)
  end

  test "R249: o feriado municipal e o estadual da praça valem; o de outra praça não" do
    sp = Agreements::Calendar.for(@sp)
    rio = Agreements::Calendar.for(Municipality.find_by!(ibge_code: "3304557"))

    assert_not sp.business?(Date.new(2027, 1, 25)), "aniversário de São Paulo"
    assert_equal Date.new(2027, 1, 26), sp.next_business(Date.new(2027, 1, 25))
    assert rio.business?(Date.new(2027, 1, 25))
    assert_not sp.business?(Date.new(2026, 7, 9)), "feriado estadual de SP"
    assert rio.business?(Date.new(2026, 7, 9))
  end

  test "M12: a praça é o município do endereço válido mais recente do cliente, casado pelo nome sem acento e pela UF" do
    customer = make_customer(@alfa, document: PaymentsHelper::MARIA, name: "Maria", contract_code: "CT-1")
    assert_nil Agreements::Square.municipality_for(customer)
    assert Agreements::Square.unrecognized?(customer), "sem endereço"

    old = customer.contacts.create!(tenant: @alfa, kind: "address", key: "a1", value: "Rua A, 1", city: "Rio de Janeiro", state: "RJ", origin: "screen", updated_at: 3.days.ago)
    customer.contacts.create!(tenant: @alfa, kind: "address", key: "a2", value: "Rua B, 2", city: "SAO PAULO", state: "sp", origin: "screen", updated_at: 1.day.ago)
    assert_equal @sp, Agreements::Square.municipality_for(customer)

    old.update!(updated_at: Time.current)
    assert_equal "Rio de Janeiro", Agreements::Square.municipality_for(customer).name, "o mais recentemente atualizado"
    old.update!(status: "invalid")
    assert_equal @sp, Agreements::Square.municipality_for(customer), "só o endereço válido"
  end

  test "AB9: cidade que não casa com o IBGE fica só com os dias nacionais e entra no filtro 'cidade não reconhecida'" do
    customer = make_customer(@alfa, document: PaymentsHelper::MARIA, name: "Maria", contract_code: "CT-1")
    customer.contacts.create!(tenant: @alfa, kind: "address", key: "a1", value: "Rua A, 1", city: "Atlântida", state: "SP", origin: "screen")
    recognized = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "João", contract_code: "CT-2")
    recognized.contacts.create!(tenant: @alfa, kind: "address", key: "a1", value: "Rua A, 1", city: "São Paulo", state: "SP", origin: "screen")

    assert Agreements::Square.unrecognized?(customer)
    assert_equal [ customer.id ], Customer.where(tenant_id: @alfa.id).where(Agreements::Square::UNRECOGNIZED_SQL).pluck(:id)
    assert_not Agreements::Calendar.for(Agreements::Square.municipality_for(customer)).extra_dates.any?
  end

  test "O8: a importação do administrador lê municípios e feriados, não duplica e recusa a linha inválida" do
    municipalities = write_csv([ "5300108;Brasília;DF", "1100205;Porto Velho;RO", "123;Curto;XX" ], header: %w[codigo_ibge nome uf])
    result = Agreements::CalendarImporter.new.municipalities(municipalities)
    assert_equal 2, result.processed
    assert_equal 1, result.rejected.size
    assert_equal 1, Municipality.where(ibge_code: "5300108").count

    again = Agreements::CalendarImporter.new.municipalities(municipalities)
    assert_equal 2, again.processed
    assert_equal 1, Municipality.where(ibge_code: "5300108").count

    holidays = write_csv([ "DF;;21/04/2027;Fundação de Brasília", "RO;1100205;04/01/2027;Dia do Estado", "RO;9999999;05/01/2027;Município fora da lista" ], header: %w[uf codigo_ibge data nome])
    holiday_result = Agreements::CalendarImporter.new.holidays(holidays)
    assert_equal 2, holiday_result.processed
    assert_equal 1, holiday_result.rejected.size
    assert_nil Holiday.find_by!(state: "DF").municipality_id
    assert_equal 3, TaskRun.where(name: %w[import_municipalities import_holidays]).count
  end

  test "O8: arquivo sem as colunas esperadas é recusado com o que falta" do
    file = write_csv([ "1;2" ], header: %w[a b])

    error = assert_raises(ArgumentError) { Agreements::CalendarImporter.new.holidays(file) }
    assert_includes error.message, "uf"
  end
end
