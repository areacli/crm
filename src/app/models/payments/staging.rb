module Payments
  # Monta as linhas da conferência de pagamentos ou estornos em lotes e as grava na tabela de preparação pelo `PaymentRow` (`insert_all!` do Active
  # Record). A preparação guarda o ARQUIVO LIDO, não é entidade de domínio: não passa pela auditoria (decisão 0021).
  class Staging
    COLUMNS = %i[channel_code identifier document bill_number paid_on amount_cents payment_method payment_identifier reason final_state].freeze

    # Linhas de preparação por lote; o lote é também a unidade de commit e de retomada da leitura.
    class_attribute :batch_size, instance_writer: false, default: 1000

    def initialize(import_id)
      @import_id = import_id
      @rows = []
    end

    def size = @rows.size

    def full? = size >= self.class.batch_size

    # `row` é uma linha normalizada de um dos dois validadores; o que ela não tem fica nulo.
    def add(row)
      values = row.to_h
      @rows << { import_id: @import_id, line: row.line, **COLUMNS.index_with { |column| values[column] }, ok: true }
    end

    # Grava o que está no buffer. Quem chama decide a transação (o lote inteiro, com as recusas, vai junto).
    def flush
      PaymentRow.insert_all!(@rows, returning: false) unless @rows.empty?
      @rows.clear
    end
  end
end
