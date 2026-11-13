module Payments
  # O fluxo ordenado de uma importação de pagamentos ou de estornos (R52, R53): as linhas do arquivo e, nos pagamentos, os pagamentos pendentes de antes,
  # em ordem de data, com o que fala de acordo primeiro e o pendente antes do novo. É a leitura que alimenta o `Processor` e o `ReversalProcessor`, um lote
  # por vez (decisão 0021): a ordem fica gravada na própria preparação (`payment_rows.rank`) e cada lote é uma consulta por chave
  # `(paid_on, rank, line)`, com o estado do banco do momento. SQL escrito à mão só lê; quem grava a ordem é o `PaymentRow`.
  module PaymentStream
    Sql = Portfolio::Sql

    # `rank`: 0 pendente com acordo, 1 linha do arquivo com acordo, 2 pendente, 3 linha do arquivo. A ordem do fluxo é (data, rank, linha).
    FILE_RANK = 3
    PENDING_RANK = 2
    AGREEMENT_BONUS = 2

    module_function

    # Prepara a ordem do fluxo (idempotente): tira o que uma execução anterior deixou e põe os pendentes e a prioridade dos acordos.
    def prepare(import)
      PaymentRow.where(import_id: import.id).where.not(pending_payment_id: nil).delete_all
      PaymentRow.where(import_id: import.id).update_all(rank: FILE_RANK)
      stage_pending(import) if import.payments?
      rank_agreements(import) if import.payments?
    end

    # R52: o pagamento pendente (o título ainda não estava na carteira) entra no fluxo como uma linha da preparação, com a linha negativa (única) e a posição na ordem.
    # 17, R418: o pendente leva o sistema dele (a reavaliação só olha esse sistema; o pendente cujo pai é o CRM vale em qualquer um) e o id do título; o pendente
    # reenviado com outro sistema entra com o sistema da linha de reenvio, para a conferência simular o que a confirmação vai gravar.
    def stage_pending(import)
      crm_id = SourceSystem.crm_of(import.tenant_id).id
      repointed = Repoint.targets(import)
      pending = Payment.where(tenant_id: import.tenant_id, status: "pending").where("amount_cents - reversed_cents > 0").joins(:channel).order(:id)
                       .pluck("payments.id", "payment_channels.code", :identifier, :document, :bill_number, :paid_on, Arel.sql("payments.amount_cents - payments.reversed_cents"),
                              :payment_method, :final_state, :source_system_id, :external_bill_id)
      pending.each_slice(1000).with_index do |slice, slice_index|
        PaymentRow.insert_all!(slice.each_with_index.map do |(id, code, identifier, document, number, paid_on, cents, method, final_state, system_id, external_id), index|
          system_id, external_id, number = repointed[id].first(2) + [ number.presence || repointed[id].last ] if repointed.key?(id)
          { import_id: import.id, line: slice_index * 1000 + index - pending.size, channel_code: code, identifier: identifier, document: document, bill_number: number.presence,
            paid_on: paid_on, amount_cents: cents, payment_method: method, final_state: final_state, ok: true, pending_payment_id: id, rank: PENDING_RANK,
            source_system_id: (system_id unless system_id == crm_id), external_bill_id: external_id }
        end, returning: false)
      end
    end

    # Linha cujo título é de acordo, ou cujo número é o de um acordo, vem antes das demais da mesma data (11, R230): a prioridade sobe dois pontos. Título de
    # acordo é do CRM e o número dele vale em qualquer sistema: a busca é no credor inteiro; o instrumento pago traz o título pronto (17, R417b).
    def rank_agreements(import)
      lines = Sql.rows(<<~SQL, import.tenant_id, import.tenant_id, import.tenant_id, import.id).map { |row| [ row["line"].to_i, row["pending"] ] }.uniq
        select r.line, (r.pending_payment_id is not null) as pending
        from payment_rows r
        left join customers c on c.tenant_id = ? and c.document = r.document
        left join bills bd on bd.tenant_id = ? and bd.customer_id = c.id and bd.number = r.bill_number
        left join (select number, min(id) as id from bills where tenant_id = ? group by number having count(*) = 1) bn on bd.id is null and bn.number = r.bill_number
        left join bills b on b.id = coalesce(r.target_bill_id, bd.id, bn.id)
        left join agreements ag on ag.tenant_id = #{import.tenant_id.to_i} and ag.number = r.bill_number
        where r.import_id = ? and r.ok and (b.agreement_id is not null or ag.id is not null)
      SQL
      lines.each_slice(1000) do |slice|
        PaymentRow.where(import_id: import.id, line: slice.map(&:first)).update_all("rank = rank - #{AGREEMENT_BONUS}")
      end
    end

    # Linhas do lote de pagamentos, depois do cursor `[data, rank, linha]` (ou desde o começo), com o que a baixa precisa saber do título, da promessa e do acordo
    # no banco de agora. `repeats`: quantas linhas do lote são do mesmo título. O título de cada linha vem do `BillResolver` (17, R417), como tabela de valores.
    def payments_lot(import, cursor, limit)
      keys = lot_keys(import, cursor, limit)
      return [] if keys.empty?

      Sql.rows(<<~SQL, import.id, keys.map(&:line), *([ import.tenant_id ] * 3))
        select s.rank, case when s.pending_payment_id is null then 1 else 0 end as src, s.line, s.pending_payment_id as payment_id, ch.id as channel_id, s.identifier, s.document,
               s.bill_number, s.paid_on, s.amount_cents, s.payment_method, s.final_state, s.source_system_id, s.external_bill_id, b.number as found_number,
               case when pp.id is null then b.id end as bill_id, pp.id as promise_id, count(b.id) over (partition by b.id) as repeats, b.contract_id, b.amount_cents as bill_amount, b.paid_cents,
               b.status as bill_status, b.agreement_id as bill_agreement_id, b.origin_agreement_id as bill_origin_agreement_id, ag.id as agreement_ref_id, hold.agreement_id as held_agreement_id,
               hold.state as held_state
        from (select * from payment_rows where import_id = ? and line in (?)) s
        join payment_channels ch on ch.tenant_id = #{import.tenant_id.to_i} and ch.code = s.channel_code
        -- R50, R50a e 17, R417 a R417b: o título da linha, achado antes, em Ruby, dentro do sistema dela. A lista vem pronta porque agregar os títulos do credor
        -- dentro desta consulta fazia o planejador repetir a agregação por linha (25 s por lote com 200 mil títulos).
        left join #{resolved_bills(import, keys)} on rb.line = s.line
        left join bills b on b.id = rb.bill_id
        -- 10, R194: o número da promessa no lugar do número do título (DP8); único dentro do credor (MT-10).
        left join payment_promises pp on pp.tenant_id = ? and pp.number = s.bill_number
        -- 11, R230: o número do acordo sem sufixo; e o acordo que prende o título original (pagamento direto, R232).
        left join agreements ag on ag.tenant_id = ? and ag.number = s.bill_number
        left join (select ab.bill_id, ab.agreement_id, a.state from agreement_bills ab join agreements a on a.id = ab.agreement_id where ab.held and a.tenant_id = ?) hold on hold.bill_id = b.id
        order by s.paid_on, s.rank, s.line
      SQL
    end

    # Linhas do lote de estornos (R60 a R63) com o pagamento estornado, o título, a promessa e o acordo dele no banco de agora.
    def reversals_lot(import, cursor, limit)
      lines = lot_keys(import, cursor, limit).map(&:line)
      return [] if lines.empty?

      Sql.rows(<<~SQL, import.id, lines, *([ import.tenant_id ] * 2))
        select r.rank, r.line, r.identifier, r.paid_on as reversed_on, r.amount_cents, r.reason,
               p.id as payment_id, p.channel_id, p.status as payment_status, p.amount_cents as payment_amount, p.applied_cents, p.credit_cents + p.moved_to_credit_cents as credit_cents,
               p.reversed_cents, p.credit_reversed_cents, p.bill_id, p.promise_id, p.agreement_id, b.kind as bill_kind, b.agreement_id as bill_agreement_id,
               (a.reversing_since is not null and a.reverted_at is null) as ag_reversing, a.state as ag_state, hold.agreement_id as held_agreement_id, hold.state as held_state, p.promise_counted,
               coalesce(b.contract_id, pr.contract_id, (select min(contract_id) from agreement_bills where agreement_id = p.agreement_id)) as contract_id, b.amount_cents as bill_amount,
               b.paid_cents, b.paid_on as bill_paid_on, b.status as bill_status, b.withdrawn_at
        from (select * from payment_rows where import_id = ? and line in (?)) r
        join payment_channels ch on ch.tenant_id = #{import.tenant_id.to_i} and ch.code = r.channel_code
        join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
        left join bills b on b.id = p.bill_id
        left join payment_promises pr on pr.id = p.promise_id
        left join agreements a on a.id = coalesce(b.agreement_id, p.agreement_id)
        left join (select ab.bill_id, ab.agreement_id, ha.state from agreement_bills ab join agreements ha on ha.id = ab.agreement_id where ab.held and ha.tenant_id = ?) hold on hold.bill_id = b.id
        order by r.paid_on, r.rank, r.line
      SQL
    end

    # As linhas do lote pela chave `(data, rank, linha)`, pelo índice `payment_rows (import_id, ok, paid_on, rank, line)`, com o que acha o título de cada uma.
    # Primeiro só as chaves (uma leitura barata); a consulta que junta títulos, promessas e acordos recebe a lista pronta, com o tamanho certo para o planejador (a
    # comparação de chave composta, sozinha, faz o planejador achar que sobra uma linha e escolher um plano que repete a agregação de títulos a cada linha).
    def lot_keys(import, cursor, limit)
      after = cursor.present? ? "and (paid_on, rank, line) > (?::date, ?::int, ?::int)" : ""
      Sql.rows(<<~SQL, import.id, *cursor, limit).map do |row|
        select line, bill_number, document, source_system_id, external_bill_id, target_bill_id
        from payment_rows where import_id = ? and ok #{after} order by paid_on, rank, line limit ?
      SQL
        BillResolver::Key.new(line: row["line"].to_i, number: row["bill_number"], document: row["document"], system_id: row["source_system_id"]&.to_i,
                              external_id: row["external_bill_id"], target_id: row["target_bill_id"]&.to_i)
      end
    end

    # O título de cada linha do lote, como tabela de valores `(line, bill_id)` para a consulta do lote: só inteiros.
    def resolved_bills(import, keys)
      found = BillResolver.new(import.tenant_id).resolve(keys)
      return "(select null::int as line, null::bigint as bill_id where false) as rb" if found.empty?

      "(values #{found.map { |line, bill_id| "(#{line.to_i}::int, #{bill_id.to_i}::bigint)" }.join(',')}) as rb(line, bill_id)"
    end
  end
end
