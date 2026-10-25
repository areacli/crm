require "test_helper"

# R125 (normalização para comparar duplicidade) e R111 (formatos inválidos): telefone, e-mail e endereço.
class Registry::NormalizerTest < ActiveSupport::TestCase
  def key(kind, raw) = Registry::Normalizer.public_send(kind, raw).key

  test "R125: o telefone vira DDD + número, sem o 55 e sem o 0 (com a operadora) da frente" do
    [ "+55 (11) 98765-4321", "011 98765-4321", "0 15 11 98765-4321", "(11) 98765-4321", "55 11 98765-4321" ].each do |raw|
      assert_equal "11987654321", key(:phone, raw), raw
    end
    assert_equal "1187654321", key(:phone, "(11) 8765-4321"), "o 9 dos celulares antigos não é acrescentado (DC4)"
    assert_not_equal key(:phone, "(11) 8765-4321"), key(:phone, "(11) 98765-4321")
  end

  test "R125: o DDD 55 não é confundido com o código do país" do
    assert_equal "55987654321", key(:phone, "(55) 98765-4321")
  end

  test "R125: número sem DDD é guardado como veio, com o aviso, e só é igual a outro sem DDD" do
    parsed = Registry::Normalizer.phone("98765-4321")

    assert_equal "987654321", parsed.key
    assert_equal "telefone sem DDD", parsed.warning
    assert_not_equal parsed.key, key(:phone, "(11) 98765-4321")
    assert_equal "98765-4321", parsed.value, "o contato é exibido como foi digitado"
  end

  test "R111: telefone com menos de 8 dígitos, dígitos demais ou DDD inválido é recusado com o motivo" do
    assert_equal "menos de 8 dígitos", Registry::Normalizer.phone("ramal 12")
    assert_equal "dígitos demais", Registry::Normalizer.phone("1234567890123456")
    assert_equal "DDD inválido", Registry::Normalizer.phone("(10) 98765-4321")
  end

  test "R125: e-mail sem espaços nas pontas e em minúsculas; sem @ e domínio é recusado (R111)" do
    assert_equal "maria@exemplo.com.br", key(:email, " Maria@Exemplo.com.br ")
    assert_equal "Maria@Exemplo.com.br", Registry::Normalizer.email(" Maria@Exemplo.com.br ").value
    assert_equal "formato inválido", Registry::Normalizer.email("maria.exemplo.com.br")
    assert_equal "formato inválido", Registry::Normalizer.email("maria@exemplo")
  end

  test "R125: 'R. das Flores, 120' e 'Rua das Flores, nº 120' com o mesmo CEP são o mesmo endereço" do
    one = Registry::Normalizer.address(street: "R. das Flores", number: "120", city: "São Paulo", state: "sp", zip: "01001-000")
    two = Registry::Normalizer.address(street: "Rua das Flores", number: "nº 120", complement: "ap 3", district: "Centro", city: "São Paulo", state: "SP", zip: "01001000")

    assert_equal one.key, two.key
    assert_equal "Rua das Flores, 120, ap 3, Centro, São Paulo/SP, CEP 01001-000", two.value
  end

  test "R125: abreviações do começo do logradouro por extenso, e número vazio vira s/n" do
    { "Av. Paulista" => "AVENIDA PAULISTA", "Tv Sete" => "TRAVESSA SETE", "Pça da Sé" => "PRACA DA SE", "Rod. BR-116" => "RODOVIA BR 116",
      "Est. do Sol" => "ESTRADA DO SOL", "Al. Santos" => "ALAMEDA SANTOS" }.each do |street, expected|
      assert_equal expected, Registry::Normalizer.street_key(street)
    end
    assert_equal "01001000|s/n|RUA A", Registry::Normalizer.address(street: "Rua A", number: "", city: "X", state: "SP", zip: "01001-000").key
  end

  test "R110 e R111: endereço incompleto, CEP ou UF inválidos são recusados com o motivo; tudo vazio não é endereço" do
    assert_nil Registry::Normalizer.address(street: "", city: " ")
    assert_equal "incompleto (falta logradouro, cidade e CEP)", Registry::Normalizer.address(street: "", city: "", state: "SP", number: "1", zip: "")
    assert_equal "CEP inválido", Registry::Normalizer.address(street: "Rua A", city: "X", state: "SP", zip: "0100-000")
    assert_equal "UF inválida", Registry::Normalizer.address(street: "Rua A", city: "X", state: "XX", zip: "01001-000")
  end
end
