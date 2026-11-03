module Queues
  # O "Próximo" (15, R353, R354): encerra as travas vencidas, devolve a entrega aberta do operador se houver (uma por vez) e, nas filas dele
  # pela estratégia, pega o primeiro disponível que ainda casa com a fila. Roda no papel do usuário: o RLS só deixa ver, e por isso só
  # entregar, o que está pra ele (14, R314). Os índices únicos parciais impedem dois operadores no mesmo sujeito: quem perde a corrida tenta
  # o próximo candidato (`SKIP LOCKED` evita a espera, decisão 1 do plano técnico da camada 19).
  class NextDelivery
    CANDIDATES = 5

    Result = Data.define(:delivery, :reason)

    def initialize(user) = @user = user

    def call
      tenant_ids = @user.tenant_ids_with("record_contact_attempts")
      strategy = Strategy.new(@user, tenant_ids)
      return Result.new(nil, :no_group) if strategy.queues.empty?

      ApplicationRecord.transaction do
        now = Time.current
        QueueDelivery.open.where(tenant_id: tenant_ids).where(locked_until: ...now).update_all(ended_at: now, end_reason: "expired", updated_at: now)
        open = QueueDelivery.open.find_by(user_id: @user.id)
        return Result.new(open, nil) if open

        strategy.ordered.each do |queue|
          delivery = take(queue, now)
          next unless delivery

          strategy.served!(queue)
          Broadcast.changed(queue.tenant)
          return Result.new(delivery, nil)
        end
        Result.new(nil, :empty)
      end
    end

    private
      def take(queue, now)
        3.times do
          candidates = QueuePlacement.where(work_queue_id: queue.id).where("available_at IS NULL OR available_at <= ?", now)
                                     .where.not(subject_id: QueueDelivery.open.where(subject: queue.subject).select(:subject_id))
                                     .order(:rank).limit(CANDIDATES).lock("FOR UPDATE SKIP LOCKED").to_a
          return nil if candidates.empty?

          still = Placer.reevaluate(queue.tenant, queue.subject, candidates.map(&:subject_id), framing: framing(queue))
          candidates.each do |placement|
            next unless still[placement.subject_id] == queue.id

            delivery = claim(queue, placement, now)
            return delivery if delivery
          end
        end
        nil
      end

      def framing(queue) = (@framings ||= {})[[ queue.tenant_id, queue.subject ]] ||= WorkQueue.framing(queue.tenant, queue.subject)

      def claim(queue, placement, now)
        QueueDelivery.transaction(requires_new: true) do
          QueueDelivery.create!(tenant_id: queue.tenant_id, work_queue: queue, subject: queue.subject, subject_id: placement.subject_id, user: @user,
                                delivered_at: now, locked_until: now + queue.lock_minutes.minutes)
        end
      rescue ActiveRecord::RecordNotUnique
        nil
      end
  end
end
