// htmx (HTML do servidor, trocado por trechos) e o WebSocket (eventos de invalidação do Action Cable). Sem Turbo, sem Stimulus.
import htmx from "htmx.org"
import "cable"
import "painel"
import "menu"
import "detalhes"

window.htmx = htmx

// Sem JavaScript embutido na página (CSP): nada de `hx-on` com código, nada de avaliação de texto.
htmx.config.allowEval = false

// Toda requisição do htmx leva o token CSRF do Rails (a página o declara em <meta name="csrf-token">).
document.addEventListener("htmx:configRequest", (evento) => {
  const token = document.querySelector("meta[name=csrf-token]")?.content
  if (token) evento.detail.headers["X-CSRF-Token"] = token
})

// Erro que não é de validação (acesso recusado, não encontrado, falha do servidor): a navegação por link (hx-boost) troca a página pela página de erro; o pedido
// de um trecho (painel, filtro, aba) mostra um aviso no alto da página, em vez de não fazer nada.
const aviso = (texto) => {
  const principal = document.querySelector("main")
  if (!principal) return

  principal.querySelector("[data-erro-de-pedido]")?.remove()
  const aside = document.createElement("aside")
  aside.className = "aviso"
  aside.dataset.tone = "danger"
  aside.dataset.erroDePedido = ""
  aside.setAttribute("role", "alert")
  aside.textContent = texto
  principal.prepend(aside)
}
document.addEventListener("htmx:beforeSwap", (evento) => {
  const status = evento.detail.xhr.status
  if (status < 400 || status === 422 || status === 204) return

  if (evento.detail.boosted && (evento.detail.xhr.getResponseHeader("Content-Type") || "").includes("text/html") && evento.detail.xhr.responseText.length > 0) {
    evento.detail.shouldSwap = true
    evento.detail.isError = false
  } else if (status === 429) aviso("Muitas tentativas. Aguarde alguns minutos e tente de novo.")
  else if (status >= 500) aviso("Algo deu errado do nosso lado. Tente de novo em instantes.")
  else aviso(status === 404 || status === 403 ? "Não foi possível abrir: o item não existe ou você não tem acesso." : "Não foi possível concluir a ação. Atualize a página e tente de novo.")
})
document.addEventListener("htmx:sendError", () => aviso("Sem conexão com o servidor. Verifique a rede e tente de novo."))

// Erro de validação (422) troca o trecho, para o formulário voltar com as mensagens.
document.addEventListener("htmx:beforeSwap", (evento) => {
  if (evento.detail.xhr.status === 422) {
    evento.detail.shouldSwap = true
    evento.detail.isError = false
  }
})
