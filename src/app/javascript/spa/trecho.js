// Carrega um trecho do Rails numa aba, janela ou diálogo e monta os componentes dele.
import { acompanhar, falhaNoLugar, mensagemDeFalha } from "spa/espera"
import { montar } from "spa/montagem"

const $ = window.jQuery

const CARREGANDO = '<div class="espera"><span class="girando" aria-hidden="true"></span> <span class="espera-texto">Carregando…</span></div>'

// Os painéis de `combobox` ficam no `body`: saem antes de o trecho ser trocado, senão sobram nós a cada troca.
export function limpar(alvo) {
  alvo.find(".combo-f").each(function () { $(this).combo("destroy") })
}

// Refaz um trecho vivo da tela (`data-spa-vivo`, como o andamento da importação) sem o "Carregando…": o que está na tela fica até a resposta chegar.
export function refazerVivo(trecho) {
  const url = trecho.data("spa-vivo")
  trecho.data("pedido")?.abort()
  const pedido = $.ajax({ url, dataType: "html", headers: { "X-CRM-Fragmento": "1" } })
  trecho.data("pedido", pedido)
  pedido.done((html) => {
    if (trecho.data("pedido") !== pedido) return
    const novo = $("<div>").html(html).children()
    limpar(trecho)
    trecho.replaceWith(novo)
    montar(novo)
  })
}

// Trecho vivo que acabou de entrar em andamento (a contagem do "Conferir", a conferência do impacto) com `data-spa-vivo-confere`: uma conferência meio segundo
// depois, para o resultado que ficou pronto antes de a tela ouvir o aviso do WebSocket. Uma só, sem repetir: o resto vem pelo aviso.
export function conferirVivos(raiz) {
  raiz.find("[data-spa-vivo-confere]").addBack("[data-spa-vivo-confere]").each(function () {
    const trecho = this
    setTimeout(() => { if (document.contains(trecho)) refazerVivo($(trecho)) }, 500)
  })
}

// Só a carga mais recente escreve no alvo (design system, 7.2, resposta atrasada descartada): a aba refeita pelo tempo real e logo levada a outro endereço
// (a confirmação dos pagamentos e, em seguida, "Importar estornos" na mesma aba) recebia as duas respostas, e a que chegava por último ficava na tela.
export function carregar(alvo, url, { cabecalhos = {}, depois } = {}) {
  limpar(alvo)
  alvo.html(CARREGANDO)
  const anterior = alvo.data("carga")
  const pedido = $.ajax({ url, dataType: "html", headers: cabecalhos })
  alvo.data("carga", pedido)
  anterior?.abort()
  const atual = () => alvo.data("carga") === pedido
  acompanhar(alvo, pedido, { ainda: () => alvo.find(".espera-texto").text("Ainda carregando…") })
  return pedido
    .done((html) => {
      if (!atual()) return
      alvo.html(html)
      montar(alvo)
      conferirVivos(alvo)
      depois?.(alvo)
    })
    .fail((xhr) => {
      if (!atual() || xhr.status === 401 || xhr.status === 409) return
      alvo.trigger("espera:falhou")
      falhaNoLugar(alvo, mensagemDeFalha(xhr, "carregar"), () => carregar(alvo, url, { cabecalhos, depois }))
    })
}

// O título vem do próprio trecho: `data-titulo`, ou o `h1` da barra de página.
export const tituloDe = (alvo) => alvo.find("[data-titulo]").first().data("titulo") || alvo.find("h1").first().text()
