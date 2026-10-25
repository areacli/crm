require "test_helper"

# Tetos de desconto por componente e escolha (11, R207, R209) e o esquema das políticas.
class Agreements::CapsTest < ActiveSupport::TestCase
  test "R209: a metade de cada teto é para baixo, em pontos inteiros, e o limite nunca passa do teto do segmento" do
    caps = { "installment" => { "fine" => 75, "interest" => 100, "fees" => 1 }, "cash" => { "fine" => 51 } }

    half = Agreements::Caps.half(caps)
    assert_equal [ 37, 50, 0, 25 ], [ half["installment"]["fine"], half["installment"]["interest"], half["installment"]["fees"], half["cash"]["fine"] ]
    clamped = Agreements::Caps.clamp({ "installment" => { "fine" => 90, "interest" => 20 } }, caps)
    assert_equal [ 75, 20, 0 ], [ clamped["installment"]["fine"], clamped["installment"]["interest"], clamped["installment"]["principal"] ]
  end

  test "R207: componente sem valor vale zero e o normalizado traz os sete componentes (cinco do valor atualizado e dois herdados do acordo sobre acordo, R250) nas duas colunas" do
    normalized = Agreements::Caps.normalize({ "cash" => { "correction" => 30 } })

    assert_equal 30, normalized["cash"]["correction"]
    assert_equal 0, normalized["installment"]["principal"]
    assert_equal 7, normalized["cash"].size
    assert_equal 0, Agreements::Caps.get(nil, "cash", "fine")
  end

  test "R207: só aceita componente conhecido, coluna conhecida e pontos inteiros de 0 a 100" do
    assert Agreements::Caps.valid?(Agreements::Caps.blank)
    assert_not Agreements::Caps.valid?({ "installment" => { "fine" => 101 } })
    assert_not Agreements::Caps.valid?({ "installment" => { "fine" => 12.5 } })
    assert_not Agreements::Caps.valid?({ "installment" => { "multa" => 10 } })
    assert_not Agreements::Caps.valid?({ "avista" => { "fine" => 10 } })
    assert_not Segment.new(agreement_caps: { "cash" => { "fine" => -1 } }).tap(&:valid?).errors[:agreement_caps].empty?
  end

  test "R210: política com valor fora da lista cai no padrão, e o percentual da tolerância tem teto de 100%" do
    setting = TenantSetting.new(agreement_policies: { "break_form" => "inventada", "tolerance_agreement" => { "kind" => "percent", "value" => 20_000 } })

    assert_equal "installments_follow", Agreements::Policies.value(setting, "break_form")
    assert_equal 100, Agreements::Policies.tolerance_cents(setting, "agreement", 50_000)
    assert_equal 1_000, Agreements::Policies.tolerance_cents(TenantSetting.new(agreement_policies: { "tolerance_agreement" => { "kind" => "percent", "value" => 200 } }), "agreement", 50_000)
  end

  test "R210: os números dos acordos e dos títulos de acordo têm formato próprio, e o da carga de carteira é recusado" do
    assert Agreements.number?("ACD-000123")
    assert Agreements.number?("ACD-000123-00")
    assert Agreements.number?("ACD-000123-Q")
    assert Agreements.number?("ACD-000123-E2")
    assert_not Agreements.number?("NF-1024")
    assert_not Agreements.number?("PRM-000123")
    assert_equal "ACD-000007", Agreements.format_number(7)
  end

  test "R249: município e feriado validam UF, código do IBGE e unicidade" do
    Municipality.create!(ibge_code: "3550308", name: "São Paulo", state: "SP")

    assert_not Municipality.new(ibge_code: "123", name: "Curto", state: "SP").valid?
    assert_not Municipality.new(ibge_code: "3550309", name: "sao paulo", state: "SP").valid?, "o nome sem acento e em minúsculas é único dentro da UF"
    assert Municipality.new(ibge_code: "4106902", name: "São Paulo", state: "PR").valid?
    holiday = Holiday.create!(state: "SP", date: Date.new(2027, 7, 9), name: "Revolução")
    assert_not Holiday.new(state: "SP", date: Date.new(2027, 7, 9), name: "Outra").valid?
    assert_raises(ActiveRecord::RecordNotUnique) { Holiday.new(state: "SP", date: holiday.date, name: "Outra").save!(validate: false) }
    assert_not Holiday.new(state: "sp", date: Date.new(2027, 7, 10), name: "x").valid?
  end
end
