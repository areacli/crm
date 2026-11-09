// Partida da SPA (decisão 0028). O aviso de tela pequena é só HTML e CSS; aqui se decide se a aplicação carrega. O EasyUI só vem quando a tela serve, e ao girar o tablet a aplicação abre.
const pequena = window.matchMedia("(max-width: 1023.98px) and (pointer: coarse)")
let iniciado = false

if (Math.max(screen.width, screen.height) >= 1024) {
  document.getElementById("aviso-titulo").textContent = "Gire o aparelho para usar o CRM"
  document.getElementById("aviso-texto").textContent = "Na posição deitada, a tela tem o tamanho necessário."
}

const carregarScript = (src) => new Promise((pronto, falha) => {
  const script = document.createElement("script")
  script.src = src
  script.async = false
  script.onload = pronto
  script.onerror = falha
  document.body.appendChild(script)
})

async function iniciar() {
  if (iniciado) return
  iniciado = true
  for (const src of JSON.parse(document.querySelector('meta[name="spa-scripts"]').content)) {
    await carregarScript(src)
    // O jQuery carregado depois do `load` da página precisa soltar o `ready` para o EasyUI.
    if (window.jQuery?.holdReady && !window.jQuery.fn.tabs) window.jQuery.holdReady(false)
  }
  const { partida } = await import("spa/aplicacao")
  partida()
}

if (!pequena.matches) iniciar()
pequena.addEventListener("change", (evento) => {
  if (evento.matches) return
  iniciar()
  window.jQuery?.fn.layout && window.jQuery("#app").layout("resize")
})
