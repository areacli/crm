module Payments
  # Acha o título de cada linha de um lote de pagamentos (R50, R50a; 17, R417 a R417b). A regra é Ruby sobre leituras do Active Record, uma por passo e por
  # lote, e o resultado entra na consulta do lote como tabela de valores (`PaymentStream.payments_lot`). Em ordem:
  #
  #   1. o título a que o instrumento foi emitido (`target_id`), sem procurar pelo número (R417b);
  #   2. o id do título no sistema da linha, quando ela o traz (R417); se o id não está na carteira, o pagamento fica pendente, sem tentar o número;
  #   3. documento e número, dentro do sistema da linha; mais de um título deixa o pagamento pendente (R417);
  #   4. pagador terceiro: o título cujo número é único naquele sistema (R417a).
  #
  # A linha sem sistema e a linha com número de promessa ou de acordo (`PRM-`, `ACD-`) valem em qualquer sistema: os passos 3 e 4 olham o credor inteiro.
  class BillResolver
    Key = Data.define(:line, :number, :document, :system_id, :external_id, :target_id) do
      def anywhere? = system_id.nil? || Promises.number?(number) || Agreements.number?(number)
    end

    def initialize(tenant_id)
      @tenant_id = tenant_id
    end

    # `keys`: as linhas do lote. Devolve `{ linha => id do título }`; a linha sem título achado fica de fora (pagamento pendente, promessa ou acordo).
    def resolve(keys)
      found = {}
      by_target(keys.select(&:target_id), found)
      rest = keys.reject { |key| found.key?(key.line) }
      with_id, by_number = rest.partition(&:external_id)
      by_external_id(with_id, found)
      by_document_and_number(by_number.select(&:number), found)
      found
    end

    private
      def bills = Bill.where(tenant_id: @tenant_id)

      def by_target(keys, found)
        return if keys.empty?

        known = bills.where(id: keys.map(&:target_id).uniq).pluck(:id).to_set
        keys.each { |key| found[key.line] = key.target_id if known.include?(key.target_id) }
      end

      # Índice: `bills (tenant_id, source_system_id, external_id)`, único.
      def by_external_id(keys, found)
        return if keys.empty?

        ids = bills.where(source_system_id: keys.map(&:system_id).uniq, external_id: keys.map(&:external_id).uniq).pluck(:source_system_id, :external_id, :id)
                   .to_h { |system_id, external_id, id| [ [ system_id, external_id ], id ] }
        keys.each { |key| (id = ids[[ key.system_id, key.external_id ]]) && found[key.line] = id }
      end

      # Índices: `customers (tenant_id, document)` e `bills (customer_id)`.
      def by_document_and_number(keys, found)
        return if keys.empty?

        customers = Customer.where(tenant_id: @tenant_id, document: keys.filter_map(&:document).uniq).pluck(:document, :id).to_h
        owned = bills.where(customer_id: customers.values, number: keys.map(&:number).uniq).pluck(:customer_id, :number, :source_system_id, :id)
                     .group_by { |customer_id, number, _, _| [ customer_id, number ] }
        third_party = []
        keys.each do |key|
          candidates = (owned[[ customers[key.document], key.number ]] || []).select { |_, _, system_id, _| key.anywhere? || system_id == key.system_id }
          # Mais de um título do mesmo cliente com o mesmo número (id próprio): ambíguo, o pagamento fica pendente e não cai na regra do pagador terceiro.
          next found[key.line] = candidates.first.last if candidates.one?

          third_party << key if candidates.empty?
        end
        by_unique_number(third_party, found)
      end

      # R417a: o número que só um título tem naquele sistema (ou no credor inteiro, na linha que vale em qualquer sistema). Sem índice por número: a leitura
      # percorre os títulos do credor uma vez por lote, só para os números que o passo anterior não resolveu.
      def by_unique_number(keys, found)
        return if keys.empty?

        counted = bills.where(number: keys.map(&:number).uniq).group(:number, :source_system_id).pluck(:number, :source_system_id, Arel.sql("count(*)"), Arel.sql("min(bills.id)"))
        in_system = counted.to_h { |number, system_id, count, id| [ [ number, system_id ], [ count, id ] ] }
        anywhere = counted.group_by(&:first).transform_values { |rows| [ rows.sum { |row| row[2] }, rows.map(&:last).min ] }
        keys.each do |key|
          count, id = key.anywhere? ? anywhere[key.number] : in_system[[ key.number, key.system_id ]]
          found[key.line] = id if count == 1
        end
      end
  end
end
