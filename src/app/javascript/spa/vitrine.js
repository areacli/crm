// Carrossel da entrada na demonstração (`layouts/_vitrine`): troca devagar, para ao passar o mouse ou ao focar, e não anda sozinho para quem pede menos movimento.
const INTERVALO = 7000

export function ligarVitrine() {
  const vitrine = document.querySelector("[data-vitrine]")
  if (!vitrine) return
  const telas = [...vitrine.querySelectorAll("[data-vitrine-tela]")]
  const pontos = [...vitrine.querySelectorAll("[data-vitrine-ir]")]
  let atual = 0
  let relogio = null
  const mostrar = (indice) => {
    atual = (indice + telas.length) % telas.length
    telas.forEach((tela, i) => {
      tela.toggleAttribute("data-atual", i === atual)
      if (i === atual) tela.removeAttribute("aria-hidden"); else tela.setAttribute("aria-hidden", "true")
    })
    pontos.forEach((ponto, i) => { if (i === atual) ponto.setAttribute("aria-current", "true"); else ponto.removeAttribute("aria-current") })
  }
  const parar = () => { clearInterval(relogio); relogio = null }
  const andar = () => {
    parar()
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    relogio = setInterval(() => {
      // A entrada fechou: o carrossel não trabalha atrás das abas.
      if (document.querySelector("#entrada").hidden) return
      mostrar(atual + 1)
    }, INTERVALO)
  }
  vitrine.addEventListener("click", (evento) => {
    const botao = evento.target.closest("button")
    if (!botao) return
    if (botao.dataset.vitrinePasso) mostrar(atual + Number(botao.dataset.vitrinePasso))
    else mostrar(Number(botao.dataset.vitrineIr))
  })
  vitrine.addEventListener("mouseenter", parar)
  vitrine.addEventListener("mouseleave", andar)
  vitrine.addEventListener("focusin", parar)
  vitrine.addEventListener("focusout", andar)
  andar()
}
