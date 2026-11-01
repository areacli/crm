// Linha com detalhe (padrões de interface, revisão 25, P26): a seta antes da primeira coluna abre e fecha a faixa de detalhe logo abaixo da linha;
// a do cabeçalho abre e fecha todas as da tabela. Os detalhes abertos continuam abertos quando o trecho se refaz pelo htmx (WebSocket, paginação).
const alternar = (botao, abrir) => {
  const linha = document.getElementById(botao.getAttribute("aria-controls"))
  if (!linha) return
  linha.hidden = !abrir
  botao.setAttribute("aria-expanded", String(abrir))
  botao.setAttribute("aria-label", `${abrir ? "Esconder" : "Mostrar"} detalhes de ${botao.dataset.objeto}`)
}

const sincronizarTodos = (tabela) => {
  const todos = tabela?.querySelector("[data-alternar-todos]")
  if (!todos) return
  const botoes = [...tabela.querySelectorAll("[data-alternar-detalhe]")]
  const abertos = botoes.length > 0 && botoes.every((botao) => botao.getAttribute("aria-expanded") === "true")
  todos.setAttribute("aria-expanded", String(abertos))
  todos.setAttribute("aria-label", `${abertos ? "Esconder" : "Mostrar"} os detalhes de todas as linhas`)
}

document.addEventListener("click", (evento) => {
  const botao = evento.target.closest?.("[data-alternar-detalhe], [data-alternar-todos]")
  if (!botao) return
  const tabela = botao.closest("table")
  const abrir = botao.getAttribute("aria-expanded") !== "true"
  if (botao.hasAttribute("data-alternar-todos")) tabela.querySelectorAll("[data-alternar-detalhe]").forEach((linha) => alternar(linha, abrir))
  else alternar(botao, abrir)
  sincronizarTodos(tabela)
})

let abertos = []
document.addEventListener("htmx:beforeSwap", (evento) => {
  if (evento.detail.boosted) return
  abertos = [...document.querySelectorAll("[data-alternar-detalhe][aria-expanded=true]")].map((botao) => botao.getAttribute("aria-controls"))
})
document.addEventListener("htmx:afterSettle", () => {
  abertos.forEach((id) => {
    const botao = document.querySelector(`[data-alternar-detalhe][aria-controls="${CSS.escape(id)}"]`)
    if (botao && botao.getAttribute("aria-expanded") !== "true") {
      alternar(botao, true)
      sincronizarTodos(botao.closest("table"))
    }
  })
  abertos = []
})
