// Diálogos e gravação (padrões de interface, revisão 38; design system, 7.2): a máscara cobre só a aba, o botão espera a resposta, e o que foi digitado fica se der errado.
import { confirmarDescarte, atualizar, abrir as abrirAba, navegar as navegarNaAba } from "spa/abas"
import { acompanhar } from "spa/espera"
import { esc } from "spa/formatos"
import { montar } from "spa/montagem"
import { carregar, limpar } from "spa/trecho"

const $ = window.jQuery

const IMPRESSAO = [/\/exportacao(\?|$)/, /\/termo(\?|$)/]

function irPara(destino) {
  if (!IMPRESSAO.some((padrao) => padrao.test(destino))) return abrirAba(destino)
  const caixa = $('<p>A página está pronta. <a target="_blank" rel="noopener">Abrir a página para imprimir</a></p>')
  caixa.find("a").attr("href", destino)
  $.messager.alert("Página para imprimir", caixa.prop("outerHTML"), "info")
}

function avisar({ aviso, tom }) {
  if (aviso) $.messager.show({ title: tom === "danger" ? "Atenção" : "Feito", msg: esc(aviso), timeout: 3200, showType: "slide" })
}

function ajustar(corpo, reg) {
  const form = corpo.find("form.dialogo")
  if (!form.length) return corpo.dialog("center")
  // O modal tem a altura do conteúdo; o painel, a da aba.
  const opcoes = { width: form.data("largura-do-dialogo"), height: form.data("altura-da-aba") ? reg.raiz.height() - 24 : "auto" }
  corpo.dialog("resize", opcoes).dialog("setTitle", `<span class="titulo-do-dialogo" title="${esc(form.data("titulo"))}">${esc(form.data("titulo"))}</span>`).dialog("center")
  // O foco vai ao primeiro campo; sem campo (nada a escolher), ao primeiro link ou botão, para o Esc e o Tab valerem dentro do diálogo.
  const campo = form.find("input:not([type=hidden]), textarea").first()
  ;(campo.length ? campo : form.find("a[href], button").first()).trigger("focus")
}

function trocarForaDeBanda(form, html) {
  const recebido = $("<div>").html(html)
  recebido.find("[data-fora-de-banda]").each(function () {
    const atual = form.find(`[id="${this.id}"]`)
    limpar(atual)
    const novo = $(this).removeAttr("data-fora-de-banda")
    atual.replaceWith(novo)
    montar(novo)
  })
}

function falhaAoGravar(form, xhr) {
  const texto = xhr.status === 0 ? "Sem resposta do servidor. Confira se foi gravado antes de repetir." : "Não foi possível gravar. O que você digitou continua aqui."
  form.find(".falha-ao-gravar").remove()
  // Fora de diálogo (a simulação), a mensagem vai junto do botão que gravou.
  const lugar = form.find(".dialogo-corpo")
  const aviso = $('<p class="falha-ao-gravar" role="alert"></p>').text(texto)
  lugar.length ? aviso.prependTo(lugar) : aviso.insertBefore(form.find("button[type=submit]").last().parent())
}

// Grava o formulário uma vez só. 204: fecha e atualiza. 422: refaz o formulário. Sem resposta: diz que não se sabe se gravou.
export function enviar(form, reg, corpo, { depois } = {}) {
  if (form.data("enviando")) return
  const botao = form.find("button[type=submit]")
  // Com arquivo (importação), o envio vai em `FormData`, e o percentual enviado aparece junto do botão (design system, 7.2: enviar arquivo).
  const comArquivo = form.find("input[type=file]").length > 0
  const dados = comArquivo ? new FormData(form[0]) : form.serialize()
  form.data("enviando", true).find(".dialogo-corpo").addClass("travado")
  botao.prop("disabled", true).addClass("carregando")
  reg.gravando += 1
  const ainda = $('<span class="espera-texto" role="status"></span>')
  const envio = comArquivo ? {
    processData: false, contentType: false,
    xhr() {
      const xhr = $.ajaxSettings.xhr()
      ainda.insertBefore(botao).text("Enviando o arquivo… 0%")
      xhr.upload.addEventListener("progress", (evento) => {
        if (!evento.lengthComputable) return
        const feito = Math.floor((evento.loaded / evento.total) * 100)
        ainda.text(feito < 100 ? `Enviando o arquivo… ${feito}%` : "Arquivo enviado. Recebendo a resposta…")
      })
      return xhr
    },
  } : {}
  const pedido = $.ajax({ url: form.attr("action"), method: "POST", data: dados, dataType: "html", ...envio })
  acompanhar(form, pedido, { ainda: () => { if (!comArquivo) ainda.text("Ainda gravando…").insertBefore(botao) } })
  pedido.always(() => ainda.remove())
  pedido
    .done((_html, _situacao, xhr) => {
      reg.sujo = false
      const evento = JSON.parse(xhr.getResponseHeader("X-CRM-Evento") || "{}")
      corpo?.dialog("close")
      avisar(evento)
      // Ação que termina noutra página (`HX-Redirect`): a de imprimir abre noutra aba do navegador, as do CRM numa aba da casca.
      const destino = xhr.getResponseHeader("HX-Redirect")
      if (destino) irPara(destino)
      else if (depois) depois(evento)
      else if (evento.navegar && evento.mesma_aba) navegarNaAba(reg, evento.navegar)
      else if (evento.navegar) abrirAba(evento.navegar, { recarregar: true })
      // A tela se refaz pelo mesmo caminho do tempo real: a lista refaz só o resultado, com o filtro; o resto, a aba.
      else if (evento.atualizar) atualizar(reg)
    })
    .fail((xhr) => {
      form.removeData("enviando").find(".dialogo-corpo").removeClass("travado")
      botao.prop("disabled", false).removeClass("carregando")
      if (xhr.status === 422 && corpo) {
        limpar(corpo)
        corpo.html(xhr.responseText)
        montar(corpo)
        ajustar(corpo, reg)
      } else if (xhr.status === 422 && form.closest("[data-refazer-no-erro]").length) {
        // Tela que o servidor refaz inteira na recusa (simulação de acordo): a resposta toma o lugar da tela, com o que foi digitado.
        const caixa = form.closest("[data-refazer-no-erro]")
        const novo = $("<div>").html(xhr.responseText).find("[data-refazer-no-erro]").first()
        limpar(caixa)
        caixa.replaceWith(novo)
        montar(novo)
      } else if (xhr.status === 422) {
        // Fora de diálogo (entrada, formulário solto): o formulário refeito pelo servidor toma o lugar do enviado.
        const novo = $("<div>").html(xhr.responseText).children()
        limpar(form)
        form.replaceWith(novo)
        montar(novo.parent())
      } else if (xhr.status !== 401 && xhr.status !== 409) {
        falhaAoGravar(form, xhr)
      }
    })
    .always(() => { reg.gravando -= 1 })
}

// Campos que dependem de uma escolha (design system, 7.2): o rodapé diz que os campos estão sendo atualizados, gravar espera a resposta, o pedido novo
// cancela o anterior, e a falha oferece "Tentar de novo".
export function refazerDependentes(form, url) {
  form.data("dependentes")?.abort()
  let situacao = form.find("footer .situacao-dos-campos")
  if (!situacao.length) situacao = $('<span class="espera-texto situacao-dos-campos" role="status"></span>').prependTo(form.find("footer"))
  situacao.text("Atualizando os campos…")
  const gravar = form.find("button[type=submit]").prop("disabled", true)
  const pedido = $.ajax({ url, data: form.serialize(), dataType: "html" })
  form.data("dependentes", pedido)
  pedido
    .done((html) => {
      if (form.data("dependentes") !== pedido) return
      trocarForaDeBanda(form, html)
      situacao.empty()
    })
    .fail((xhr, estado) => {
      if (estado === "abort" || form.data("dependentes") !== pedido) return
      situacao.text(xhr.status === 0 ? "Sem resposta do servidor. " : "Não foi possível atualizar os campos. ")
      $('<button type="button" data-variant="link" data-size="small">Tentar de novo</button>').on("click", () => refazerDependentes(form, url)).appendTo(situacao)
    })
    .always(() => { if (form.data("dependentes") === pedido) gravar.prop("disabled", false) })
}

export function abrir(url, reg, { depois } = {}) {
  // O foco volta a quem abriu (o botão ou o item do menu da linha, que some com o menu: aí, o botão "⋯" dele).
  const quemAbriu = document.activeElement?.closest("[popover]")?.previousElementSibling || document.activeElement
  const corpo = $('<div class="dialogo-conteudo"></div>').appendTo(reg.raiz)
  corpo.dialog({
    title: "Carregando…", inline: true, modal: true, width: 480, height: 220, constrain: true, shadow: false, closed: false,
    collapsible: false, minimizable: false, maximizable: false, resizable: false,
    onBeforeClose() {
      if (!reg.sujo) return true
      confirmarDescarte(() => { reg.sujo = false; corpo.dialog("close") })
      return false
    },
    onClose() {
      $(this).dialog("destroy")
      if (quemAbriu?.isConnected) quemAbriu.focus()
    },
  })
  // Esc e o clique na máscara (só a da aba) fecham, como o Cancelar; com algo escrito, pergunta antes.
  // O Esc para aqui: o `$.messager` ouve o Esc no documento e fecharia na hora a pergunta de descartar que este mesmo Esc abre.
  corpo.closest(".window").on("keydown", (evento) => {
    if (evento.key !== "Escape") return
    evento.preventDefault()
    evento.stopPropagation()
    corpo.dialog("close")
  })
  corpo.closest(".window").nextAll(".window-mask").first().on("click", () => corpo.dialog("close"))
  carregar(corpo, url, { depois: () => ajustar(corpo, reg) })

  corpo.on("input", "form.dialogo", () => { reg.sujo = true })
  corpo.on("spa:mudou", "form.dialogo", function (evento, dependentes) {
    reg.sujo = true
    // O endereço vem do campo que mudou ou do bloco em volta dele (`data-spa-dependentes`).
    dependentes ||= $(evento.target).closest("[data-spa-dependentes]").data("spa-dependentes")
    if (dependentes) refazerDependentes($(this), dependentes)
  })
  corpo.on("submit", "form.dialogo", function (evento) {
    evento.preventDefault()
    enviar($(this), reg, corpo, { depois })
  })
  corpo.on("click", "[data-spa-fechar]", () => corpo.dialog("close"))
}
