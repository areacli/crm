require "test_helper"

class Portfolio::RowValidatorTest < ActiveSupport::TestCase
  setup { @validator = Portfolio::RowValidator.new }

  # `validate("valor" => "0,00")`: as chaves de texto chegam como argumentos nomeados, e as de símbolo (extra, short) são as marcas da linha.
  def validate(overrides = {}, **flags)
    overrides = overrides.merge(flags.select { |chave, _| chave.is_a?(String) })
    row = Portfolio::CsvFile::Row.new(line: 7, values: csv_line(overrides), extra: flags[:extra] || false, short: flags[:short] || false)
    @validator.validate(row)
  end

  test "linha válida vira linha normalizada" do
    parsed, reason = validate("documento" => "529.982.247-25", "valor" => "1.234,56", "vencimento" => "1/9/2026", "telefone" => "")

    assert_nil reason
    assert_equal "52998224725", parsed.document
    assert_equal 123_456, parsed.amount_cents
    assert_equal Date.new(2026, 9, 1), parsed.due_date
    assert_nil parsed.phone
    assert_equal 7, parsed.line
  end

  test "motivos de recusa" do
    {
      { "documento" => "111.111.111-11" } => "CPF inválido",
      { "valor" => "0,00" } => "valor deve ser maior que zero",
      { "valor" => "12,345" } => "valor com mais de duas casas decimais",
      { "vencimento" => "31/02/2026" } => "data inválida",
      { "nome" => "" } => "nome obrigatório",
      { "titulo" => "" } => "título obrigatório",
      { "nome" => "x" * 301 } => "nome acima de 300 caracteres",
      { "email" => "e" * 255 } => "e-mail acima de 254 caracteres",
      { "papel" => "chefe" } => "papel inválido: chefe"
    }.each do |overrides, expected|
      parsed, reason = validate(overrides)

      assert_nil parsed, overrides.inspect
      assert_equal expected, reason
    end
    assert_equal "linha com mais colunas que o cabeçalho", validate({}, extra: true).last
    assert_equal "linha incompleta", validate({}, short: true).last
  end

  test "papéis: titular, responsável financeiro ou os dois; vazio vale os dois" do
    assert_nil validate("papel" => "").first.roles
    assert_equal "holder", validate("papel" => "Titular").first.roles
    assert_equal "financial_responsible", validate("papel" => "responsável financeiro").first.roles
    assert_equal "financial_responsible,holder", validate("papel" => "titular / Responsavel Financeiro").first.roles
  end
end
