// Carrossel da entrada na demonstração (`layouts/_vitrine`): troca devagar, para ao passar o mouse ou ao focar, tem "Pausar" à vista e não anda
// sozinho para quem pede menos movimento. As abas de texto escolhem a tela pelo nome.
const INTERVALO = 7000

export function ligarVitrine() {
  const vitrine = document.querySelector("[data-vitrine]")
  if (!vitrine) return
  const telas = [...vitrine.querySelectorAll("[data-vitrine-tela]")]
  const abas = [...vitrine.querySelectorAll("[data-vitrine-ir]")]
  const pausar = vitrine.querySelector("[data-vitrine-pausar]")
  const legenda = vitrine.querySelector(".vitrine-legenda")
  const poucoMovimento = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  let atual = 0
  let relogio = null
  let pausado = poucoMovimento
  const mostrar = (indice) => {
    atual = (indice + telas.length) % telas.length
    telas.forEach((tela, i) => {
      tela.toggleAttribute("data-atual", i === atual)
      if (i === atual) tela.removeAttribute("aria-hidden"); else tela.setAttribute("aria-hidden", "true")
    })
    abas.forEach((aba, i) => { if (i === atual) aba.setAttribute("aria-current", "true"); else aba.removeAttribute("aria-current") })
    legenda.querySelector("strong").textContent = telas[atual].dataset.titulo
    legenda.querySelector("span").textContent = telas[atual].dataset.texto
  }
  const parar = () => { clearInterval(relogio); relogio = null }
  const andar = () => {
    parar()
    if (pausado) return
    relogio = setInterval(() => {
      // A entrada fechou: o carrossel não trabalha atrás das abas.
      if (document.querySelector("#entrada").hidden) return
      mostrar(atual + 1)
    }, INTERVALO)
  }
  const marcarPausa = () => {
    pausar.setAttribute("aria-pressed", String(pausado))
    pausar.querySelector("span").textContent = pausado ? "Continuar" : "Pausar"
    pausar.querySelector("svg").outerHTML = document.querySelector(`#vitrine-icone-${pausado ? "play" : "pause"}`).innerHTML
  }
  vitrine.addEventListener("click", (evento) => {
    const botao = evento.target.closest("button")
    if (!botao) return
    if (botao === pausar) { pausado = !pausado; marcarPausa(); return }
    mostrar(Number(botao.dataset.vitrineIr))
  })
  vitrine.addEventListener("mouseenter", parar)
  vitrine.addEventListener("mouseleave", andar)
  vitrine.addEventListener("focusin", parar)
  vitrine.addEventListener("focusout", andar)
  if (poucoMovimento) marcarPausa()
  andar()
}

// Os botões dos usuários da demonstração preenchem o e-mail e a senha e entram pelo mesmo formulário.
export function ligarEntrarComo() {
  document.querySelectorAll("[data-entrar-como]").forEach((botao) => {
    botao.addEventListener("click", () => {
      const formulario = document.querySelector("#entrada-form")
      formulario.querySelector("#entrada-email").value = botao.dataset.email
      formulario.querySelector("#entrada-senha").value = botao.dataset.senha
      formulario.requestSubmit()
    })
  })
}
