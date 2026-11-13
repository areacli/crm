module Portfolio
  # Como uma linha da carga casa com o que está gravado (17, R403, R414, R415): sempre dentro do sistema da importação, e pela chave do sistema. Em
  # chave natural, o título é documento e número e o contrato é o código; em id próprio, valem o id do título e o do contrato. Devolve trechos de SQL
  # de leitura para a conferência (decisão 0021), com os apelidos `r` (linha da preparação), `c` (cliente), `b` (título) e `k` (contrato). Só inteiros
  # da própria importação são escritos no texto; o predicado sobre `external_id` é literal porque os índices são parciais (decisão 0010):
  # `bills (tenant_id, source_system_id, customer_id, number) WHERE external_id IS NULL`, `bills (tenant_id, source_system_id, external_id) WHERE
  # external_id IS NOT NULL`, os dois equivalentes de `contracts` e `import_rows (import_id, external_bill_id)`.
  class Matching
    def initialize(import)
      @import_id = import.id.to_i
      @tenant_id = import.tenant_id.to_i
      @system_id = import.source_system_id.to_i
      @own_id = import.source_system.key_own_id?
    end

    def own_id? = @own_id

    # Os títulos do sistema da importação (R414): o batimento e a comparação não alcançam os dos outros.
    def system_bills = "b.tenant_id = #{@tenant_id} and b.source_system_id = #{@system_id} and b.external_id is #{'not ' if own_id?}null"

    # Junta a linha ao cliente e ao título gravado. `kind`: "join" (só as linhas com título) ou "left join" (todas as linhas).
    def bill_joins(kind = "left join")
      customer = "#{kind} customers c on c.tenant_id = #{@tenant_id} and c.document = r.document"
      return "#{customer} #{kind} bills b on #{system_bills} and b.customer_id = c.id and b.number = r.number" unless own_id?

      # Em id próprio o título é achado pelo id, de quem quer que seja (a troca de devedor é mudança a confirmar, R405); `c` é o cliente do documento
      # da linha.
      "#{kind} bills b on #{system_bills} and b.external_id = r.external_bill_id #{customer}"
    end

    # O contrato declarado na linha, no sistema da importação.
    def contract_join(kind = "left join", contract = "k")
      base = "#{kind} contracts #{contract} on #{contract}.tenant_id = #{@tenant_id} and #{contract}.source_system_id = #{@system_id}"
      return "#{base} and #{contract}.external_id = r.external_contract_id and #{contract}.external_id is not null" if own_id?

      "#{base} and #{contract}.code = r.contract and #{contract}.external_id is null"
    end

    # A linha traz outro contrato que não o do título (`k` é o contrato do título).
    def contract_changed = own_id? ? "k.external_id is distinct from r.external_contract_id" : "coalesce(k.code, '') <> coalesce(r.contract, '')"

    # O título `b` (do cliente `c`) veio no arquivo, numa linha aceita ou recusada: é o que o batimento não retira (R11, R15). A linha recusada por
    # nomes divergentes guarda o documento inteiro (R7).
    def present = rows_exist("true")

    # Veio numa linha recusada (R15).
    def present_rejected = rows_exist("not r.ok")

    # Veio numa linha aceita.
    def present_accepted = "exists (select 1 from import_rows r where r.import_id = #{@import_id} and r.ok and #{row_is_bill})"

    # Quantos contratos por omissão a carga cria (R9a, R404): não existem em id próprio (R401).
    def omission_count = own_id? ? "select 0 as n" : "select count(distinct document) as n from import_rows where import_id = #{@import_id} and ok and contract is null"

    # A coluna que identifica o contrato na linha.
    def contract_key = own_id? ? "external_contract_id" : "contract"

    private
      def row_is_bill = own_id? ? "r.external_bill_id = b.external_id" : "r.document = c.document and r.number = b.number"

      # Em chave natural, a consulta é a de sempre (uma só passagem pelo índice `import_rows (import_id, document, number)`); em id próprio, a
      # chave e o documento guardado usam índices diferentes.
      def rows_exist(filter)
        rows = "select 1 from import_rows r where r.import_id = #{@import_id}"
        return "exists (#{rows} and #{filter} and r.document = c.document and (r.number = b.number or r.keep_document))" unless own_id?

        "(exists (#{rows} and #{filter} and #{row_is_bill}) or exists (#{rows} and r.keep_document and r.document = c.document))"
      end
  end
end
