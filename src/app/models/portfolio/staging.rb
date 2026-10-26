module Portfolio
  # Monta as linhas da conferência (e os contatos) em lotes e as grava na tabela de preparação pelo `ImportRow` e `ImportContact`
  # (`insert_all!` do Active Record). A preparação guarda o ARQUIVO LIDO, não é entidade de domínio: não passa pela auditoria (decisão 0021).
  class Staging
    # Linhas de preparação por lote; o lote é também a unidade de commit e de retomada da leitura.
    class_attribute :batch_size, instance_writer: false, default: 1000

    def initialize(import_id)
      @import_id = import_id
      @rows = []
      @contacts = []
    end

    def size = @rows.size

    def full? = size >= self.class.batch_size

    def add(row, name_key)
      @rows << { import_id: @import_id, line: row.line, document: row.document, number: row.number, name: row.name, name_key: name_key, contract: row.contract,
                 due_date: row.due_date, amount_cents: row.amount_cents, description: row.description, ok: true, keep_document: false, roles: row.roles,
                 product: row.product, penalty_cents: row.penalty_cents, interest_cents: row.interest_cents, correction_cents: row.correction_cents,
                 other_cents: row.other_cents }
    end

    # Contatos da linha (06, R109). `tenant_keys`: telefone e e-mail do credor, normalizados, para marcar o contato que é igual ao do credor
    # (R126). Devolve os avisos novos da linha.
    def add_contacts(row, tenant_keys)
      row.contacts.filter_map do |contact|
        tenant_contact = tenant_keys[contact.kind] == contact.key
        @contacts << { import_id: @import_id, line: row.line, document: row.document, kind: contact.kind, key: contact.key, value: contact.value,
                       street: contact.street, number: contact.number, complement: contact.complement, district: contact.district, city: contact.city,
                       state: contact.state, zip: contact.zip, tenant_contact: tenant_contact }
        "#{contact.kind == 'phone' ? 'telefone' : 'e-mail'} igual ao do credor (entra inválido)" if tenant_contact
      end
    end

    # Linha recusada, mas com documento e título legíveis: guarda a chave para o título não ser retirado (R15).
    def add_key_only(line, document, number)
      @rows << { import_id: @import_id, line: line, document: document, number: number, name: nil, name_key: nil, contract: nil, due_date: nil, amount_cents: nil,
                 description: nil, ok: false, keep_document: false, roles: nil, product: nil, penalty_cents: nil, interest_cents: nil, correction_cents: nil,
                 other_cents: nil }
    end

    # Grava o que está no buffer. Quem chama decide a transação (o lote inteiro, com recusas e avisos, vai junto).
    def flush
      ImportRow.insert_all!(@rows, returning: false) unless @rows.empty?
      ImportContact.insert_all!(@contacts, returning: false) unless @contacts.empty?
      @rows.clear
      @contacts.clear
    end
  end
end
