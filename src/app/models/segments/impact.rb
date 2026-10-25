module Segments
  # Conferência do impacto (R154): roda o cálculo com a proposta e compara com o segmento vigente de cada contrato; nada é gravado.
  # Devolve, por par "de → para", quantos contratos e quanto saldo (em cobrança, sem encargos) mudam, e quantos são mistos (caso de exceção).
  class Impact
    Row = Data.define(:from_id, :to_id, :contracts, :balance_cents, :mixed)

    attr_reader :proposal, :rows

    def initialize(proposal)
      @proposal = proposal
      calc = Calculator.new(proposal.tenant, entries: proposal.entries, policy: proposal.policy).sql
      @rows = Portfolio::Sql.rows(<<~SQL).map { |r| Row.new(r["from_id"], r["to_id"], r["contracts"].to_i, r["balance_cents"].to_i, r["mixed"].to_i) }
        select old_segment_id as from_id, new_segment_id as to_id, count(*) as contracts, coalesce(sum(balance_cents), 0) as balance_cents,
               count(*) filter (where person_type = 'mixed') as mixed
        from (#{calc}) calc where old_segment_id is distinct from new_segment_id group by 1, 2 order by 1 nulls first, 2
      SQL
    end

    def total = rows.sum(&:contracts)
    def balance_cents = rows.sum(&:balance_cents)
    def mixed = rows.sum(&:mixed)

    # Por segmento de destino: quantos contratos e quanto saldo entram e de onde vêm; "Saem" é o inverso.
    def entering = rows.group_by(&:to_id)
    def leaving = rows.group_by(&:from_id)
  end
end
