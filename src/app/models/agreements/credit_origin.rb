module Agreements
  # De onde saiu o crédito de um pagamento estornado (11, R233, R62, AB4, AK2): o estorno consome primeiro o que ainda está disponível dessa origem; o que passa disso foi usado (num
  # acordo, num título pela ficha) ou transferido a outro contrato. O uso consome primeiro o crédito disponível há mais tempo (R232b), então a atribuição é uma simulação do livro do
  # contrato em ordem: cada origem entra com o que gerou, os lançamentos de estorno saem da origem deles e os demais (usado, transferido) saem do mais antigo.
  module CreditOrigin
    # `available`: o que ainda está disponível da origem; `awaiting` e `blocked`: o que está nos outros estados; `consumptions`: [[lançamento, centavos]] do uso mais recente para o mais
    # antigo. Mutável: quem planeja vários estornos do mesmo pagamento na mesma confirmação vai tirando o que já planejou.
    Position = Struct.new(:available, :awaiting, :blocked, :consumptions)
    # O que o estorno de `cents` do crédito do pagamento faz: `available`, `awaiting`, `blocked` (de cada balde), `uses` ([lançamento, centavos]) e `unattributed` (o que não se explica).
    Plan = Data.define(:available, :awaiting, :blocked, :uses, :unattributed)

    module_function

    # Planeja o estorno de `cents` do crédito do pagamento e tira o planejado da posição.
    def plan(position, cents)
      available = [ cents, position.available ].min.tap { |part| cents -= part; position.available -= part }
      awaiting = [ cents, position.awaiting ].min.tap { |part| cents -= part; position.awaiting -= part }
      blocked = [ cents, position.blocked ].min.tap { |part| cents -= part; position.blocked -= part }
      uses = []
      position.consumptions = position.consumptions.filter_map do |entry, part|
        next [ entry, part ] unless cents.positive?

        used = [ cents, part ].min
        cents -= used
        uses << [ entry, used ]
        [ entry, part - used ] if part > used
      end
      Plan.new(available, awaiting, blocked, uses, cents)
    end

    # A posição de uma origem (o pagamento) no livro do contrato.
    def position(contract_id, payment_id)
      queue = [] # as origens disponíveis, da mais antiga para a mais nova: { id:, payment_id:, left:, uses: [[lançamento, centavos]] }
      awaiting = Hash.new(0)
      blocked = Hash.new(0)
      Credit.where(contract_id: contract_id).order(:occurred_at, :id).each do |entry|
        case entry.bucket
        when "awaiting" then awaiting[entry.payment_id] += entry.amount_cents
        when "blocked" then blocked[entry.payment_id] += entry.amount_cents
        else
          if entry.amount_cents.positive?
            queue << { id: entry.id, payment_id: entry.payment_id, left: entry.amount_cents, uses: [] }
          elsif entry.payment_id && (entry.reversal? || entry.moved?)
            consume(queue.select { |origin| origin[:payment_id] == entry.payment_id }, -entry.amount_cents, nil)
          else
            consume(queue, -entry.amount_cents, entry)
          end
        end
      end
      mine = queue.select { |origin| origin[:payment_id] == payment_id }
      Position.new(mine.sum { |origin| origin[:left] }, [ awaiting[payment_id], 0 ].max, [ blocked[payment_id], 0 ].max,
                   mine.flat_map { |origin| origin[:uses] }.sort_by { |entry, _| [ -entry.occurred_at.to_f, -entry.id ] })
    end

    def consume(origins, cents, entry)
      origins.each do |origin|
        break unless cents.positive?

        part = [ origin[:left], cents ].min
        next unless part.positive?

        origin[:left] -= part
        cents -= part
        origin[:uses] << [ entry, part ] if entry
      end
    end
  end
end
