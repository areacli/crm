// Esconder e mostrar o menu lateral na tela larga (design system, revisões 7 e 9). A escolha vai num cookie, que o servidor lê para a próxima
// página já nascer no mesmo estado. A ficha do cliente tem o cookie dela (`menu_ficha`, recolhido por padrão); as outras páginas, o `menu`.
// O botão diz qual cookie e em que estado o servidor desenhou a página: como o hx-boost não troca os atributos do <body>, depois de cada troca
// o estado do <body> é refeito a partir do botão.
const aplicar = (recolhido) => {
  if (recolhido) document.body.dataset.menu = "recolhido"
  else delete document.body.dataset.menu
}

document.addEventListener("click", (evento) => {
  const botao = evento.target.closest?.("[data-alternar-menu]")
  if (!botao) return
  const esconder = document.body.dataset.menu !== "recolhido"
  aplicar(esconder)
  botao.setAttribute("aria-expanded", String(!esconder))
  botao.setAttribute("aria-label", esconder ? "Mostrar o menu" : "Esconder o menu")
  const seguro = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${botao.dataset.menuCookie || "menu"}=${esconder ? "recolhido" : "aberto"}; path=/; max-age=31536000; SameSite=Lax${seguro}`
})

document.addEventListener("htmx:afterSettle", () => {
  const botao = document.querySelector("[data-alternar-menu]")
  if (botao) aplicar(botao.getAttribute("aria-expanded") === "false")
})
