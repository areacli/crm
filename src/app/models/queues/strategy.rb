module Queues
  # As filas de um operador na ordem em que o "Próximo" as tenta (15, R353), pela estratégia dele: em ordem (a posição gravada, depois a
  # ordem dos grupos), pesos (rodízio ponderado: a cada rodada, cada fila ganha o seu peso em crédito e a de mais crédito vem primeiro; a que
  # entregou perde a soma dos pesos) ou uma de cada vez (começa depois da última que entregou).
  class Strategy
    def initialize(user, tenant_ids)
      @user = user
      @tenant_ids = tenant_ids
      @strategy = QueueStrategy.for(user)
    end

    attr_reader :strategy

    # As filas dos grupos do operador nos credores em que ele tem a 7, grupo a grupo (ordem alfabética), cada um na ordem das suas filas.
    def queues
      @queues ||= QueueGroupQueue.joins(:queue_group, :work_queue)
                                 .where(queue_group_id: QueueGroupUser.where(user_id: @user.id).select(:queue_group_id))
                                 .where(queue_groups: { tenant_id: @tenant_ids }, work_queues: { active: true, delivers: true })
                                 .order("queue_groups.name", :position).includes(:work_queue).map(&:work_queue).uniq
    end

    def ordered
      list = queues
      case @strategy.mode
      when "weighted" then list.sort_by.with_index { |queue, index| [ -credit(queue), index ] }
      when "round_robin"
        last = list.index { |queue| queue.id == @strategy.cursor["last"] }
        last ? list.rotate(last + 1) : list
      else
        positions = Array(@strategy.entries).each_with_index.to_h { |entry, index| [ entry["queue_id"], index ] }
        list.sort_by.with_index { |queue, index| [ positions.fetch(queue.id, positions.size + index) ] }
      end
    end

    # Depois de uma entrega da fila `queue`: guarda onde parou.
    def served!(queue)
      return if @strategy.mode == "ordered"

      cursor = @strategy.cursor.dup
      if @strategy.mode == "round_robin"
        cursor["last"] = queue.id
      else
        credits = queues.to_h { |item| [ item.id.to_s, credit(item) ] }
        credits[queue.id.to_s] -= queues.sum { |item| @strategy.weight_of(item.id) }
        cursor["credits"] = credits
      end
      @strategy.update!(cursor: cursor)
    end

    private
      def credit(queue) = @strategy.cursor.fetch("credits", {}).fetch(queue.id.to_s, 0).to_i + @strategy.weight_of(queue.id)
  end
end
