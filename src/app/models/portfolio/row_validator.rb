module Portfolio
  # Valida um registro canônico da carteira contra as regras de identificação e validação (R1 a R6) e os limites de tamanho de campo. Não conhece o
  # formato de quem enviou: o que o decodificador não conseguiu converter chega em `format_problems`, e entra aqui na mesma ordem das demais regras.
  # Devolve [linha normalizada, nil] ou [nil, motivo da recusa].
  class RowValidator
    # Limites de caracteres por campo (especificação 01, formato da planilha).
    LIMITS = { "nome" => 300, "titulo" => 100, "contrato" => 100, "descricao" => 300, "email" => 254, "telefone" => 60, "produto" => 100,
               **Registry::LoadContacts::PHONES.drop(1).index_with { 60 }, **Registry::LoadContacts::EMAILS.drop(1).index_with { 254 } }.freeze
    FIELD_NAMES = { "documento" => "documento", "nome" => "nome", "titulo" => "título", "vencimento" => "vencimento", "valor" => "valor",
                    "telefone" => "telefone", "email" => "e-mail", "contrato" => "contrato", "descricao" => "descrição", "papel" => "papel", "produto" => "produto" }.freeze

    # Ids remotos (17, R401): até 100 caracteres. O do título e o do contrato são obrigatórios em sistema de id próprio.
    ID_NAMES = { "id_titulo" => "id do título", "id_contrato" => "id do contrato", "id_cliente" => "id do cliente" }.freeze
    ID_LIMIT = 100

    # `own_id`: o sistema da carga é de id próprio. Em chave natural, o leitor nem entrega `id_titulo` e `id_contrato` (colunas ignoradas).
    def initialize(own_id: false) = @own_id = own_id

    def validate(record)
      values = record.raw
      return [ nil, "linha com mais colunas que o cabeçalho" ] if record.extra
      return [ nil, "linha incompleta" ] if record.short

      Layout::REQUIRED.each { |field| return [ nil, "#{FIELD_NAMES[field]} obrigatório" ] if values[field].blank? }
      Layout::OWN_ID_ONLY.each { |field| return [ nil, "#{ID_NAMES[field]} obrigatório neste sistema" ] if values[field].blank? } if @own_id
      problem = Document.problem(values["documento"])
      return [ nil, problem ] if problem

      LIMITS.each do |field, max|
        return [ nil, "#{FIELD_NAMES.fetch(field, field)} acima de #{max} caracteres" ] if values[field].to_s.length > max
      end
      ID_NAMES.each { |field, name| return [ nil, "#{name} acima de #{ID_LIMIT} caracteres" ] if values[field].to_s.length > ID_LIMIT }
      # 10, R187a: o número da promessa chega no lugar do número do título; um título não pode ter o formato dele.
      return [ nil, "título no formato de número de promessa (PRM-)" ] if Promises.number?(values["titulo"])
      return [ nil, "título no formato de número de acordo (ACD-)" ] if Agreements.number?(values["titulo"])

      %i[due_date amount roles surcharges].each { |field| return [ nil, record.format_problems[field] ] if record.format_problems[field] }

      surcharges = record.surcharges
      [ ParsedRow.new(line: record.position, document: record.document, name: values["nome"], contacts: record.contacts, warnings: record.warnings, contract: values["contrato"].presence, number: values["titulo"], due_date: record.due_date,
                      amount_cents: record.amount_cents, description: values["descricao"].presence, roles: record.roles, product: values["produto"].presence,
                      penalty_cents: surcharges[0], interest_cents: surcharges[1], correction_cents: surcharges[2], other_cents: surcharges[3],
                      external_bill_id: (values["id_titulo"].presence if @own_id), external_contract_id: (values["id_contrato"].presence if @own_id),
                      external_customer_id: values["id_cliente"].presence), nil ]
    end
  end
end
