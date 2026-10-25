# Acessibilidade (WCAG 2.2 AA) em cada tela, com o axe-core (o documento do design system do projeto, seção 9): injeta o axe na página aberta e falha
# com a lista de violações. O axe vem na gem `axe-core-api`; a execução usa o Capybara com o Cuprite, sem a camada WebDriver da gem.
module Acessibilidade
  TAGS = %w[wcag2a wcag2aa wcag21a wcag21aa wcag22aa].freeze

  def self.fonte_do_axe
    @fonte_do_axe ||= Pathname(Gem.loaded_specs.fetch("axe-core-api").full_gem_path).join("node_modules/axe-core/axe.min.js").read
  end

  def violacoes_de_acessibilidade(contexto = "document")
    page.execute_script(Acessibilidade.fonte_do_axe)
    resultado = page.evaluate_async_script(<<~JS)
      const feito = arguments[arguments.length - 1]
      axe.run(#{contexto}, { runOnly: { type: "tag", values: #{TAGS.to_json} } }).then((r) => feito(JSON.stringify(r.violations.map((v) => ({
        id: v.id, impacto: v.impact, ajuda: v.help,
        nos: v.nodes.slice(0, 3).map((n) => n.target.join(" ") + " :: " + (n.failureSummary || "").split("\\n")[1])
      })))))
    JS
    JSON.parse(resultado).map { |v| "#{v['id']} (#{v['impacto']}): #{v['ajuda']}\n  #{v['nos'].join("\n  ")}" }
  end

  def assert_acessivel(contexto = "document")
    violacoes = violacoes_de_acessibilidade(contexto)

    assert_empty violacoes, "Violações de acessibilidade em #{page.current_path}:\n#{violacoes.join("\n")}"
  end
end
