// htmx (HTML do servidor, trocado por trechos) e o WebSocket (eventos de invalidação do Action Cable). Sem Turbo, sem Stimulus.
import htmx from "htmx.org"
import "cable"

window.htmx = htmx

// Sem JavaScript embutido na página (CSP): nada de `hx-on` com código, nada de avaliação de texto.
htmx.config.allowEval = false

// Toda requisição do htmx leva o token CSRF do Rails (a página o declara em <meta name="csrf-token">).
document.addEventListener("htmx:configRequest", (evento) => {
  const token = document.querySelector("meta[name=csrf-token]")?.content
  if (token) evento.detail.headers["X-CSRF-Token"] = token
})

// Erro de validação (422) troca o trecho, para o formulário voltar com as mensagens.
document.addEventListener("htmx:beforeSwap", (evento) => {
  if (evento.detail.xhr.status === 422) {
    evento.detail.shouldSwap = true
    evento.detail.isError = false
  }
})
