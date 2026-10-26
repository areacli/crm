// Painel compartilhado (design system, revisão 4, decisão 0022): um <dialog id="painel"> no layout, modal ou painel lateral. O htmx busca o formulário
// (hx-get com destino #painel-conteudo); aqui o diálogo abre, trava a rolagem do corpo (CSS), põe o foco no primeiro campo e devolve o foco a quem abriu.
// O corpo da página é trocado pelo hx-boost, então tudo é delegado ao `document` e o <dialog> é procurado a cada evento.
import htmx from "htmx.org"

let origem = null
let pressionadoNoFundo = false

const dialogo = () => document.getElementById("painel")

const focoInicial = (raiz) => {
  const alvo = raiz.querySelector("[autofocus]") ||
    raiz.querySelector("[aria-invalid='true']") ||
    raiz.querySelector("input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled])") ||
    raiz.querySelector("footer button:not([command])") || raiz.querySelector("button")
  alvo?.focus()
}

function abrir() {
  const caixa = dialogo()
  const miolo = caixa.querySelector("[data-painel]")
  if (!miolo) return
  caixa.dataset.variant = miolo.dataset.variant || "drawer"
  if (miolo.dataset.size) caixa.dataset.size = miolo.dataset.size; else delete caixa.dataset.size
  caixa.setAttribute("aria-labelledby", "painel-titulo")
  if (!caixa.open) caixa.showModal()
  focoInicial(caixa)
}

const guardarOrigem = (elemento) => {
  // Quem abre pode estar num menu de linha (popover) que fecha: o foco volta ao botão que abre o menu.
  const menu = elemento?.closest?.("[popover]")
  origem = menu ? document.querySelector(`[popovertarget="${menu.id}"]`) : elemento
}

document.addEventListener("htmx:beforeRequest", (evento) => {
  if (evento.detail.target?.id === "painel-conteudo" && !dialogo()?.open) guardarOrigem(evento.detail.elt)
})

document.addEventListener("htmx:afterSwap", (evento) => {
  if (evento.detail.target?.id === "painel-conteudo") abrir()
})

// Sucesso: o servidor responde 204 com HX-Trigger "painel:concluido" ({ aviso, atualizar }).
document.addEventListener("painel:concluido", (evento) => {
  dialogo()?.close()
  const { aviso, atualizar, tom } = evento.detail || {}
  // A atualização troca o conteúdo da página (inclusive a região dos avisos): o aviso aparece depois dela.
  if (atualizar) {
    htmx.ajax("GET", window.location.href, { target: "#conteudo", select: "#conteudo", swap: "outerHTML", headers: { "HX-Boosted": "true" } }).then(() => aviso && mostrarAviso(aviso, tom))
  } else if (aviso) {
    mostrarAviso(aviso, tom)
  }
})

function mostrarAviso(texto, tom = "success") {
  const regiao = document.getElementById("avisos-da-pagina")
  const modelo = document.getElementById("modelo-de-aviso")
  if (!regiao || !modelo) return
  const aviso = modelo.content.cloneNode(true)
  aviso.querySelector("p").textContent = texto
  aviso.querySelector(".aviso").dataset.tone = tom
  regiao.replaceChildren(aviso)
}

// Ao fechar (Esc, Cancelar, clique fora ou sucesso): esvazia o conteúdo e devolve o foco a quem abriu. O evento `close` não borbulha: captura.
document.addEventListener("close", (evento) => {
  if (evento.target.id !== "painel") return
  evento.target.querySelector("#painel-conteudo").replaceChildren()
  if (origem?.isConnected) origem.focus()
  origem = null
}, true)

// Clique fora fecha: só quando o clique começou e terminou no fundo (arrastar texto de um campo para fora não fecha).
document.addEventListener("mousedown", (evento) => { pressionadoNoFundo = evento.target.id === "painel" })
document.addEventListener("click", (evento) => {
  if (evento.target.id === "painel" && pressionadoNoFundo) dialogo().close()
  // Escolher uma ação do menu de linha fecha o menu.
  const item = evento.target.closest?.("[popover].menu :is(a, button)")
  if (item) setTimeout(() => item.closest("[popover]").hidePopover?.(), 0)
})
