module Portfolio
  # Grava as linhas da conferência na tabela de preparação, em lote, pelo COPY do PostgreSQL.
  class Staging
    COLUMNS = %w[import_id line document number name name_key contract due_date amount_cents description ok keep_document roles product penalty_cents interest_cents correction_cents other_cents].freeze

    def initialize(import_id, batch_size: 5000)
      @import_id = import_id
      @batch_size = batch_size
      @buffer = []
      @contact_buffer = []
    end

    def add(row, name_key)
      push [ @import_id, row.line, row.document, row.number, row.name, name_key, row.contract, row.due_date, row.amount_cents,
             row.description, "t", "f", row.roles, row.product, row.penalty_cents, row.interest_cents, row.correction_cents, row.other_cents ]
    end

    CONTACT_COLUMNS = %w[import_id line document kind key value street number complement district city state zip tenant_contact].freeze

    # Contatos da linha (06, R109), no mesmo ciclo do COPY. `tenant_keys`: telefone e e-mail do credor, normalizados, para marcar o contato que
    # é igual ao do credor (R126). Devolve os avisos novos da linha.
    def add_contacts(row, tenant_keys)
      warnings = row.contacts.filter_map do |contact|
        tenant_contact = tenant_keys[contact.kind] == contact.key
        @contact_buffer << contact_values(row, contact, tenant_contact)
        "#{contact.kind == 'phone' ? 'telefone' : 'e-mail'} igual ao do credor (entra inválido)" if tenant_contact
      end
      flush if @contact_buffer.size >= @batch_size * 2
      warnings
    end

    # Linha recusada, mas com documento e título legíveis: guarda a chave para o título não ser retirado (R15).
    def add_key_only(line, document, number)
      push [ @import_id, line, document, number, nil, nil, nil, nil, nil, nil, "f", "f", nil, nil, nil, nil, nil, nil ]
    end

    def flush
      connection = ActiveRecord::Base.connection.raw_connection
      unless @buffer.empty?
        connection.copy_data("COPY import_rows (#{COLUMNS.join(',')}) FROM STDIN") { @buffer.each { |line| connection.put_copy_data(line) } }
        @buffer.clear
      end
      return if @contact_buffer.empty?

      connection.copy_data("COPY import_contacts (#{CONTACT_COLUMNS.join(',')}) FROM STDIN") { @contact_buffer.each { |line| connection.put_copy_data(line) } }
      @contact_buffer.clear
    end

    private
      def push(values)
        @buffer << line_of(values)
        flush if @buffer.size >= @batch_size
      end

      def line_of(values) = "#{values.map { |value| value.nil? ? '\N' : escape(value.to_s) }.join("\t")}\n"

      NULLS = ("\\N\t" * 7).freeze

      # Telefone e e-mail não têm campos de endereço: a linha sai por interpolação direta, sem percorrer 14 valores.
      def contact_values(row, contact, tenant_contact)
        unless contact.kind == "address"
          return "#{@import_id}\t#{row.line}\t#{row.document}\t#{contact.kind}\t#{escape(contact.key)}\t#{escape(contact.value)}\t#{NULLS}#{tenant_contact ? 't' : 'f'}\n"
        end

        line_of([ @import_id, row.line, row.document, contact.kind, contact.key, contact.value, contact.street, contact.number, contact.complement, contact.district,
                  contact.city, contact.state, contact.zip, tenant_contact ? "t" : "f" ])
      end

      # Escapa os caracteres especiais do formato texto do COPY.
      def escape(value) = value.match?(/[\\\t\n\r]/) ? value.gsub(/[\\\t\n\r]/, "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r") : value
  end
end
