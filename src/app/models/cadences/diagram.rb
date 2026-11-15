module Cadences
  # O diagrama de raias de uma régua (21, revisão 1 das telas): as raias em ordem, com a trilha padrão por último; as colunas como marcas no eixo do
  # tempo, com o marco e o fim da janela; as ações de cada célula. No modo de análise, o resultado da última rodada concluída em cada célula.
  class Diagram
    Cell = Data.define(:lane, :column, :actions, :result)

    attr_reader :cadence, :lanes, :columns, :last_round

    def initialize(cadence, analysis: false)
      @cadence = cadence
      @lanes = cadence.lanes.includes(:segment).to_a
      @columns = cadence.columns.to_a
      @actions = cadence.live_actions.includes(:message_piece, :queue_task).order(:position).group_by { |action| [ action.cadence_lane_id, action.cadence_column_id ] }
      @analysis = analysis
      @last_round = cadence.rounds.where(state: %w[completed completed_with_failures]).order(:scheduled_for).last if analysis
      @results = analysis && @last_round ? results_of(@last_round) : {}
    end

    def analysis? = @analysis
    def cell(lane, column) = Cell.new(lane: lane, column: column, actions: @actions.fetch([ lane.id, column.id ], []), result: @results[[ lane.id, column.id ]])
    def empty_column?(column) = @lanes.none? { |lane| @actions.key?([ lane.id, column.id ]) }
    def endless? = !@columns.empty? && !empty_column?(@columns.last)
    def lane_without_actions?(lane) = @columns.none? { |column| @actions.key?([ lane.id, column.id ]) }

    # O nome da família do tipo, para a cor e o ícone do cartão (protótipo): comunicação, pagamento, negociação, trabalho e medida.
    def self.family(kind)
      case kind
      when *Catalog::COMMUNICATIONS.keys then "comunicacao"
      when "issue_instrument" then "pagamento"
      when "proposal", "promise" then "negociacao"
      when "task" then "trabalho"
      else "medida"
      end
    end


    private
      def results_of(round)
        rows = CadenceCommandItem.joins(:decision).where(cadence_decisions: { cadence_round_id: round.id })
                                 .group("cadence_decisions.cadence_lane_id", "cadence_decisions.cadence_column_id", "cadence_command_items.state").count
        rows.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) { |((lane, column, state), count), result| result[[ lane, column ]][state] += count }
      end
  end
end
