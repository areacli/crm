# Linha do tempo da ficha (padrões de interface, revisão 24): os eventos do cliente do passado até agora, o mais recente em cima, 10 por página,
# com o filtro por tipo. Hoje são dois tipos: **Atendimento** (cada acionamento, com a promessa registrada nele, e cada proposta de acordo) e
# **Distribuição** (entradas e saídas das operações, `Distributions::Timeline`, só para a equipe do credor). Com o contrato escolhido no filtro da
# ficha, só o daquele contrato. O que o usuário de operação vê, o RLS decide (14). Consultas: `contact_attempts (customer_id, contacted_at)`,
# `agreements (customer_id)` e as das distribuições; cada fonte lê só as linhas até a página pedida.
class CustomerTimeline
  PER_PAGE = 10
  KINDS = %w[atendimento distribuicao].freeze

  # Um evento: quando (`at`, para ordenar), se mostra a hora, o tipo do filtro, o que é (:contact_attempt, :agreement ou :distribution) e o registro.
  Event = Data.define(:at, :with_time, :kind, :source, :record)

  attr_reader :page, :kind

  def initialize(customer, contract: nil, kind: nil, page: 1, distributions: true)
    @customer = customer
    @contract = contract
    @distributions = distributions
    @kind = kinds.include?(kind.to_s) ? kind.to_s : nil
    @page = [ page.to_i, 1 ].max
  end

  # Os tipos que a pessoa pode filtrar: o usuário de operação não vê as distribuições.
  def kinds = @distributions ? KINDS : KINDS - [ "distribuicao" ]

  def events
    @events ||= begin
      wanted = page * PER_PAGE
      merged = sources.flat_map { |source| source.call(wanted) }
      merged.sort_by { |event| [ event.at, event.source == :distribution && event.record.entry? ? 0 : 1 ] }.reverse.drop((page - 1) * PER_PAGE).first(PER_PAGE)
    end
  end

  # A operação de origem do acionamento e da proposta (14, R318), pelo id: a etiqueta ao lado do evento.
  def origins
    @origins ||= Operation.where(id: events.filter_map { |event| event.record.try(:operation_id) unless event.source == :distribution }.uniq).index_by(&:id)
  end

  def total = @total ||= counts.sum
  def pages = [ (total / PER_PAGE.to_f).ceil, 1 ].max
  def previous_page = page > 1 ? page - 1 : nil
  def next_page = page < pages ? page + 1 : nil

  private
    def sources
      list = []
      list += [ method(:attempt_events), method(:agreement_events) ] if kind.nil? || kind == "atendimento"
      list << method(:distribution_events) if @distributions && (kind.nil? || kind == "distribuicao")
      list
    end

    def counts
      list = []
      list += [ attempts.count, agreements.count ] if kind.nil? || kind == "atendimento"
      list << distribution_list.size if @distributions && (kind.nil? || kind == "distribuicao")
      list
    end

    def attempts
      scope = ContactAttempt.where(customer_id: @customer.id)
      @contract ? scope.where(contract_id: @contract.id) : scope
    end

    def agreements
      scope = Agreement.where(customer_id: @customer.id)
      @contract ? scope.where(id: AgreementBill.joins(:bill).where(bills: { contract_id: @contract.id }).select(:agreement_id)) : scope
    end

    def attempt_events(limit)
      attempts.includes(:result, :user, :contract, :promise).order(contacted_at: :desc, id: :desc).limit(limit)
              .map { |attempt| Event.new(attempt.contacted_at, true, "atendimento", :contact_attempt, attempt) }
    end

    def agreement_events(limit)
      agreements.includes(:user).order(created_at: :desc, id: :desc).limit(limit).map { |agreement| Event.new(agreement.created_at, true, "atendimento", :agreement, agreement) }
    end

    # Poucas por cliente: a lista inteira, já do passado até hoje.
    def distribution_list
      @distribution_list ||= Distributions::Timeline.for(@customer, @contract ? [ @contract.id ] : @customer.contracts.ids)
    end

    def distribution_events(limit)
      distribution_list.first(limit).map { |event| Event.new(event.at, event.with_time, "distribuicao", :distribution, event) }
    end
end
