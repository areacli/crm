// Espera pelo servidor (design system, 7.2): todo pedido da SPA passa por aqui. Diz que começou, que terminou e como terminou; nenhuma falha é silenciosa, e dado velho não parece novo.
const $ = window.jQuery

const AINDA_DEPOIS_DE = 3000
let aoPerderSessao = () => {}
let aoPedirSenha = () => {}

export function configurar({ sessaoVencida, senhaTemporaria }) {
  aoPerderSessao = sessaoVencida
  aoPedirSenha = senhaTemporaria
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  $.ajaxSetup({ headers: { "X-CRM-Trecho": "1", "X-CSRF-Token": token } })
  $(document).ajaxError((_evento, xhr) => {
    if (xhr.status === 401) aoPerderSessao()
    if (xhr.status === 409) aoPedirSenha()
  })
}

// Acompanha um pedido num elemento: `aria-busy`, a troca de "…" por "Ainda…" e o indicador no título da aba em segundo plano (`spa/abas` escuta
// `espera:mudou`). A aba é guardada no começo: o elemento pode ter saído da tela quando o pedido termina (a recusa que refaz o formulário).
export function acompanhar(alvo, pedido, { ainda } = {}) {
  const aba = alvo.closest(".aba-raiz")
  alvo.attr("aria-busy", "true")
  aba.trigger("espera:mudou", [1])
  const relogio = ainda ? setTimeout(ainda, AINDA_DEPOIS_DE) : null
  pedido.always(() => {
    clearTimeout(relogio)
    alvo.removeAttr("aria-busy")
    aba.trigger("espera:mudou", [-1])
  })
  return pedido
}

export const mensagemDeFalha = (xhr, objeto) => {
  if (xhr.status === 0) return "Sem resposta do servidor. Confira a conexão."
  if (xhr.status === 404) return "Não encontrado, ou você não tem acesso a este registro."
  return `Não foi possível ${objeto}.`
}

// Falha no lugar do conteúdo, com **Tentar de novo**.
export function falhaNoLugar(alvo, texto, tentar) {
  const caixa = $('<div class="falha" role="alert"><p></p><button type="button" data-variant="secondary">Tentar de novo</button></div>')
  caixa.find("p").text(texto)
  caixa.find("button").on("click", tentar)
  alvo.empty().append(caixa)
}
