module Tiers
  # Conferência do impacto (13, R272): roda o enquadramento com a proposta e compara com o item vigente de cada contrato; nada é gravado.
  # Devolve, por par "de → para", quantos contratos e quanto saldo (em cobrança, sem encargos) mudam, e quantos são mistos.
  class Impact
    Row = Data.define(:from_id, :to_id, :contracts, :balance_cents, :mixed)

    attr_reader :proposal, :rows

    def initialize(proposal, today: Date.current)
      @proposal = proposal
      query = Segments::Compiler.new(proposal.tenant, today: today).classify(proposal.classified, default_id: proposal.catch_all_id)
      sql = <<~SQL
        select c.tier_id as from_id, calc.tier_id as to_id, count(*) as contracts, coalesce(sum(calc.balance_cents), 0) as balance_cents,
               count(*) filter (where calc.person_type = 'mixed') as mixed
        from (#{query.sql}) calc join contracts c on c.id = calc.contract_id
        where c.tier_id is distinct from calc.tier_id group by 1, 2 order by 1 nulls first, 2
      SQL
      @rows = Segments::Compiler.select(Segments::Compiler::Query.new(sql, query.binds)).map do |r|
        Row.new(r["from_id"], r["to_id"], r["contracts"].to_i, r["balance_cents"].to_i, r["mixed"].to_i)
      end
    end

    def total = rows.sum(&:contracts)
    def balance_cents = rows.sum(&:balance_cents)
    def mixed = rows.sum(&:mixed)

    # Por item de destino: quantos contratos e quanto saldo entram e de onde vêm; "Saem" é o inverso.
    def entering = rows.group_by(&:to_id)
    def leaving = rows.group_by(&:from_id)
  end
end
