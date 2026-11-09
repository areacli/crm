# Aviso no sino do que terminou em segundo plano (design system, 7.2), para quem pediu.
module BackgroundNotice
  module_function

  def finished(user, what:, where:)
    Notice.create!(user: user, kind: "background_finished", data: { what: what, where: where }) if user
  end

  def failed(user, what:, where:, reason:)
    Notice.create!(user: user, kind: "background_failed", data: { what: what, where: where, reason: reason }) if user
  end
end
