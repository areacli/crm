// Menu na barra superior (padrões de interface, revisão 34, P1): cada grupo é um <details> com a lista dos itens. Abrir um fecha os outros;
// clique fora, Esc e a troca de página pelo hx-boost fecham; Esc devolve o foco ao botão do grupo.
const grupos = () => document.querySelectorAll("#menu-principal details.grupo[open]")

document.addEventListener("toggle", (evento) => {
  const grupo = evento.target
  if (!grupo.matches?.("#menu-principal details.grupo") || !grupo.open) return
  grupos().forEach((outro) => { if (outro !== grupo) outro.open = false })
}, true)

document.addEventListener("click", (evento) => {
  grupos().forEach((grupo) => { if (!grupo.contains(evento.target)) grupo.open = false })
})

document.addEventListener("keydown", (evento) => {
  if (evento.key !== "Escape") return
  grupos().forEach((grupo) => {
    const tinhaFoco = grupo.contains(document.activeElement)
    grupo.open = false
    if (tinhaFoco) grupo.querySelector("summary").focus()
  })
})

document.addEventListener("htmx:beforeSwap", () => grupos().forEach((grupo) => { grupo.open = false }))
