module Portfolio
  # As colunas da planilha de carteira (formato da planilha, especificação 01), usadas pelo leitor, pela planilha-modelo e pela demonstração.
  module Layout
    REQUIRED = %w[documento nome titulo vencimento valor].freeze
    # `inicio_contrato` (01, revisão de 14/11/2026): a data de início do contrato no sistema do credor, que vira o atributo `iniciado há` da 13 e
    # pode ser o marco de uma régua (21). Fica no fim, depois dos contatos, para não mudar a posição das colunas de quem já manda a planilha.
    OPTIONAL = (%w[telefone email contrato descricao papel produto multa_credor juros_credor correcao_credor outros_credor] +
                Registry::LoadContacts::COLUMNS.excluding("telefone", "email") + %w[inicio_contrato]).freeze
    # Ids remotos (17, R401): o id do título e o do contrato só valem em sistema de id próprio; o do cliente vale nos dois tipos de chave.
    ID_COLUMNS = %w[id_titulo id_contrato id_cliente].freeze
    OWN_ID_ONLY = %w[id_titulo id_contrato].freeze

    # As colunas opcionais que o leitor aceita de um sistema. Em chave natural, `id_titulo` e `id_contrato` ficam de fora, e o leitor as lista
    # como colunas ignoradas (R401).
    def self.optional_for(system) = OPTIONAL + (system.key_own_id? ? ID_COLUMNS : ID_COLUMNS - OWN_ID_ONLY)
  end
end
