# O aviso autenticado que chega num formato que o adaptador não lê (12, revisão 5, R284s; PagBank: o formato antigo `notificationCode`) é guardado com o
# tipo `unreadable` e vai a "para conferir". A restrição do tipo ganha o valor novo; nenhuma linha existente muda.
class PaymentEventsUnreadableKind < ActiveRecord::Migration[8.1]
  OLD = %w[paid refunded canceled expired check other].freeze
  NEW = (OLD + %w[unreadable]).freeze

  def up
    remove_check_constraint :payment_events, name: "payment_events_kind"
    add_check_constraint :payment_events, "kind in (#{NEW.map { |kind| "'#{kind}'" }.join(', ')})", name: "payment_events_kind"
  end

  def down
    execute "delete from payment_events where kind = 'unreadable'"
    remove_check_constraint :payment_events, name: "payment_events_kind"
    add_check_constraint :payment_events, "kind in (#{OLD.map { |kind| "'#{kind}'" }.join(', ')})", name: "payment_events_kind"
  end
end
