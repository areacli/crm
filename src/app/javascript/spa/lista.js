// Listas montadas pelo servidor (barra `form.filtros` e o trecho `#resultado`): os filtros refazem só o trecho, com a espera à
// vista (design system, 7.2), e o filtro escolhido entra no endereço da aba, para o tempo real e o recarregar voltarem a ele. A tabela do trecho vira grade
// na montagem (`spa/grade`).
import { anotarEndereco, regDaRaiz } from "spa/abas"
import { acompanhar, falhaNoLugar, mensagemDeFalha } from "spa/espera"
import { montar } from "spa/montagem"

const $ = window.jQuery

export const urlDoFiltro = (form) => {
  const campos = form.serializeArray().filter((campo) => campo.value !== "")
  return `${form.attr("action")}${campos.length ? `?${$.param(campos)}` : ""}`
}

// Pede o trecho do resultado (`X-CRM-Fragmento`): o pedido novo cancela o anterior, e a resposta atrasada é descartada.
export function refazerResultado(raiz, url) {
  const alvo = raiz.find('[id="resultado"]').first()
  if (!alvo.length) return
  alvo.data("pedido")?.abort()
  alvo.attr("aria-busy", "true").addClass("refazendo")
  let aviso = alvo.prev(".espera-da-lista")
  if (!aviso.length) aviso = $('<p class="espera-da-lista" role="status"></p>').insertBefore(alvo)
  aviso.html('<span class="girando" aria-hidden="true"></span> Carregando…')
  const pedido = $.ajax({ url, dataType: "html", headers: { "X-CRM-Fragmento": "1" } })
  alvo.data("pedido", pedido)
  acompanhar(alvo, pedido, { ainda: () => aviso.html('<span class="girando" aria-hidden="true"></span> Ainda carregando…') })
  pedido
    .done((html) => {
      if (alvo.data("pedido") !== pedido) return
      aviso.remove()
      const novo = $("<div>").html(html).children()
      alvo.replaceWith(novo)
      montar(novo)
    })
    .fail((xhr, estado) => {
      if (estado === "abort" || alvo.data("pedido") !== pedido) return
      aviso.remove()
      // As linhas anteriores saem: dado velho não parece novo.
      alvo.removeAttr("aria-busy").removeClass("refazendo")
      if (xhr.status !== 401 && xhr.status !== 409) falhaNoLugar(alvo, mensagemDeFalha(xhr, "carregar a lista"), () => refazerResultado(raiz, url))
    })
}

function filtrar(form) {
  const raiz = form.closest(".aba-raiz")
  const url = urlDoFiltro(form)
  const reg = regDaRaiz(raiz)
  if (reg) anotarEndereco(reg, url)
  refazerResultado(raiz, url)
}

// O tempo real refaz a lista pelo endereço da aba, que tem o filtro (`spa/abas`).
$(document).on("spa:refazer-lista", ".aba-raiz", function (_evento, url) { refazerResultado($(this), url) })

// Busca e filtros: 300 ms depois da última mudança, como nas páginas do servidor.
let relogio = null
$(document).on("input change spa:mudou", ".aba-raiz form.filtros", function (evento) {
  if (evento.type === "change" && $(evento.target).is("input[type=search], input[type=text]")) return
  const form = $(this)
  clearTimeout(relogio)
  relogio = setTimeout(() => filtrar(form), 300)
})
$(document).on("submit", ".aba-raiz form.filtros", function (evento) {
  evento.preventDefault()
  clearTimeout(relogio)
  filtrar($(this))
})
