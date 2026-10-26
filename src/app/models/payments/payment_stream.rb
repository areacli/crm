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
    def stage_pending(import)
      pending = Payment.where(tenant_id: import.tenant_id, status: "pending").where("amount_cents - reversed_cents > 0").joins(:channel).order(:id)
                       .pluck("payments.id", "payment_channels.code", :identifier, :document, :bill_number, :paid_on, Arel.sql("payments.amount_cents - payments.reversed_cents"),
                              :payment_method, :final_state)
      pending.each_slice(1000).with_index do |slice, slice_index|
        PaymentRow.insert_all!(slice.each_with_index.map do |(id, code, identifier, document, number, paid_on, cents, method, final_state), index|
          { import_id: import.id, line: slice_index * 1000 + index - pending.size, channel_code: code, identifier: identifier, document: document, bill_number: number, paid_on: paid_on,
            amount_cents: cents, payment_method: method, final_state: final_state, ok: true, pending_payment_id: id, rank: PENDING_RANK }
        end, returning: false)
      end
    end

    # Linha cujo título é de acordo, ou cujo número é o de um acordo, vem antes das demais da mesma data (11, R230): a prioridade sobe dois pontos.
    def rank_agreements(import)
      lines = Sql.rows(<<~SQL, import.tenant_id, import.tenant_id, import.tenant_id, import.id).map { |row| [ row["line"].to_i, row["pending"] ] }
        select r.line, (r.pending_payment_id is not null) as pending
        from payment_rows r
        left join customers c on c.tenant_id = ? and c.document = r.document
        left join bills bd on bd.tenant_id = ? and bd.customer_id = c.id and bd.number = r.bill_number
        left join (select number, min(id) as id from bills where tenant_id = ? group by number having count(*) = 1) bn on bd.id is null and bn.number = r.bill_number
        left join bills b on b.id = coalesce(bd.id, bn.id)
        left join agreements ag on ag.tenant_id = #{import.tenant_id.to_i} and ag.number = r.bill_number
        where r.import_id = ? and r.ok and (b.agreement_id is not null or ag.id is not null)
      SQL
      lines.each_slice(1000) do |slice|
        PaymentRow.where(import_id: import.id, line: slice.map(&:first)).update_all("rank = rank - #{AGREEMENT_BONUS}")
      end
    end

    # Linhas do lote de pagamentos, depois do cursor `[data, rank, linha]` (ou desde o começo), com o que a baixa precisa saber do título, da promessa e do acordo
    # no banco de agora. `repeats`: quantas linhas do lote são do mesmo título.
    def payments_lot(import, cursor, limit)
      keys = lot_keys(import, cursor, limit)
      return [] if keys.empty?

      lines = keys.map(&:first)
      Sql.rows(<<~SQL, import.id, lines, *([ import.tenant_id ] * 5))
        select s.rank, case when s.pending_payment_id is null then 1 else 0 end as src, s.line, s.pending_payment_id as payment_id, ch.id as channel_id, s.identifier, s.document,
               s.bill_number, s.paid_on, s.amount_cents, s.payment_method, s.final_state,
               case when pp.id is null then b.id end as bill_id, pp.id as promise_id, count(b.id) over (partition by b.id) as repeats, b.contract_id, b.amount_cents as bill_amount, b.paid_cents,
               b.status as bill_status, b.agreement_id as bill_agreement_id, b.origin_agreement_id as bill_origin_agreement_id, ag.id as agreement_ref_id, hold.agreement_id as held_agreement_id,
               hold.state as held_state
        from (select * from payment_rows where import_id = ? and line in (?)) s
        join payment_channels ch on ch.tenant_id = #{import.tenant_id.to_i} and ch.code = s.channel_code
        left join customers c on c.tenant_id = ? and c.document = s.document
        left join bills bd on bd.tenant_id = ? and bd.customer_id = c.id and bd.number = s.bill_number
        -- R50a: o pagador pode ser um terceiro (o documento não é de cliente do título). Sem o título do documento, vale o título cujo número
        -- é único no credor; número que se repete entre clientes é ambíguo e o pagamento fica pendente. A lista de números únicos do lote vem pronta (ver
        -- `unique_numbers`): agregar os títulos do credor dentro desta consulta fazia o planejador repetir a agregação por linha (25 s por lote com 200 mil títulos).
        left join #{unique_numbers(import, keys.map(&:last))} on bd.id is null and bn.number = s.bill_number
        left join bills b on b.id = coalesce(bd.id, bn.id)
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
      lines = lot_keys(import, cursor, limit).map(&:first)
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

    # As linhas do lote pela chave `(data, rank, linha)`, pelo índice `payment_rows (import_id, ok, paid_on, rank, line)`: `[linha, número do título]`. Primeiro só os
    # números (uma leitura barata); a consulta que junta títulos, promessas e acordos recebe a lista pronta, com o tamanho certo para o planejador (a comparação de
    # chave composta, sozinha, faz o planejador achar que sobra uma linha e escolher um plano que repete a agregação de títulos a cada linha).
    def lot_keys(import, cursor, limit)
      after = cursor.present? ? "and (paid_on, rank, line) > (?::date, ?::int, ?::int)" : ""
      Sql.rows("select line, bill_number from payment_rows where import_id = ? and ok #{after} order by paid_on, rank, line limit ?", import.id, *cursor, limit)
         .map { |row| [ row["line"].to_i, row["bill_number"] ] }
    end

    # Os números de título do lote que são únicos no credor (R50a), como tabela de valores `(number, id)` para a consulta do lote.
    def unique_numbers(import, numbers)
      found = Sql.rows("select number, min(id) as id from bills where tenant_id = ? and number in (?) group by number having count(*) = 1", import.tenant_id, numbers.compact.uniq.presence || [ "" ])
      return "(select null::varchar as number, null::bigint as id where false) as bn" if found.empty?

      "(values #{found.map { |row| "(#{Sql.connection.quote(row['number'])}::varchar, #{row['id'].to_i}::bigint)" }.join(',')}) as bn(number, id)"
    end
  end
end
