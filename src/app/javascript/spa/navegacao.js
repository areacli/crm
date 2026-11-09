// Navegação dentro das abas: os links dos trechos continuam sendo `<a href>`; aqui se decide se o endereço abre aba, janela ou diálogo (plano, seção 5).
import * as abas from "spa/abas"
import { abrir as abrirDialogo, enviar, refazerDependentes } from "spa/dialogos"
import { abrir as abrirJanela, recarregar as recarregarJanela } from "spa/janelas"
import { montar } from "spa/montagem"
import { larguraDoDetalhe } from "spa/grade"
import { refazerResultado } from "spa/lista"
import { semMetodo } from "spa/calculo"
import { acompanhar, falhaNoLugar, mensagemDeFalha } from "spa/espera"
import { conferirVivos } from "spa/trecho"

const $ = window.jQuery

// Endereços que abrem em janela, vindos do `menu.json`.
let janelas = []
export const definirJanelas = (lista) => { janelas = lista.map((padrao) => new RegExp(padrao)) }
export const ehJanela = (url) => janelas.some((padrao) => padrao.test(abas.chaveDe(url)))

const regDe = (elemento) => abas.regDaRaiz($(elemento).closest(".aba-raiz"))

function abrirEndereco(url, reg) {
  const chave = abas.chaveDe(url)
  if (janelas.some((padrao) => padrao.test(chave))) return abrirJanela(url, reg)
  if (chave === reg.chave) return abas.navegar(reg, url)
  abas.abrir(url)
}

// Popover do menu "⋯" e do (i): sem `id`, porque duas fichas têm a mesma marcação. Fica ancorado no botão.
function abrirPopover(botao) {
  const popover = botao.nextElementSibling
  popover.togglePopover()
  if (!popover.matches(":popover-open")) return
  const caixa = botao.getBoundingClientRect()
  popover.style.margin = "0"
  popover.style.left = `${Math.max(8, Math.min(caixa.right - popover.offsetWidth, window.innerWidth - popover.offsetWidth - 8))}px`
  popover.style.top = `${Math.min(caixa.bottom + 4, window.innerHeight - popover.offsetHeight - 8)}px`
}

// P26: a seta abre o detalhe da própria tabela; o `id` da faixa se repete entre fichas abertas.
function alternarDetalhe(botao) {
  const tabela = botao.closest("table")
  const abrir = botao.getAttribute("aria-expanded") !== "true"
  const setas = botao.hasAttribute("data-alternar-todos") ? [...tabela.querySelectorAll("[data-alternar-detalhe]")] : [botao]
  setas.forEach((seta) => {
    const faixa = tabela.querySelector(`[id="${seta.getAttribute("aria-controls")}"]`)
    if (faixa) faixa.hidden = !abrir
    seta.setAttribute("aria-expanded", String(abrir))
  })
  if (botao.hasAttribute("data-alternar-todos")) botao.setAttribute("aria-expanded", String(abrir))
}

// Registro com vários campos (endereço): o formulário abre no detalhe da própria linha da grade (design system, 7.1). Grava como um diálogo; Cancelar
// devolve o detalhe como era.
function abrirNoDetalhe(link) {
  const linha = $(link).closest("tr.datagrid-row")
  const grade = linha.closest(".datagrid").find("table.datagrid-f").first()
  const indice = Number(linha.attr("datagrid-row-index"))
  grade.datagrid("expandRow", indice)
  const detalhe = grade.datagrid("getRowDetail", indice)
  if (detalhe.find("form").length) return detalhe.find("input:not([type=hidden])").first().trigger("focus")
  detalhe.data({ original: detalhe.html(), grade, indice })
  const alvo = $('<div class="detalhe-da-grade"></div>').css("width", larguraDoDetalhe(grade.closest(".tabela-em-grade")))
  detalhe.empty().append(alvo)
  import("spa/trecho").then(({ carregar }) => carregar(alvo, link.getAttribute("href"), {
    depois: () => { grade.datagrid("fixDetailRowHeight", indice).datagrid("resize"); detalhe.find("input:not([type=hidden])").first().trigger("focus") },
  }))
}

function fecharDetalhe(detalhe) {
  const { original, grade, indice } = detalhe.data()
  detalhe.html(original)
  grade.datagrid("fixDetailRowHeight", indice).datagrid("resize")
  detalhe.closest(".aba-raiz").trigger("inline:fechou")
}

// Abas internas: cada uma carrega o trecho dela na primeira vez que aparece, e a escolha faz parte do endereço da aba.
function montarAbasInternas(caixa) {
  const reg = regDe(caixa)
  const itens = $(caixa).data("abas")
  const raiz = $(caixa)
  raiz.tabs({
    fit: true, border: false, plain: true,
    onSelect(_titulo, indice) {
      const item = itens[indice]
      const painel = raiz.tabs("getTab", indice)
      if (!painel.data("carregada")) {
        painel.data("carregada", true)
        import("spa/trecho").then(({ carregar }) => carregar(painel, item.caminho, { cabecalhos: { "X-CRM-Secao": "1" } }))
      }
      if (reg && raiz.data("pronta")) abas.anotarEndereco(reg, item.caminho)
    },
  })
  itens.forEach((item) => {
    const contagem = item.contagem === null || item.contagem === undefined ? "" : ` (${item.contagem})`
    raiz.tabs("add", { title: `${item.titulo}${contagem}`, selected: false, content: "" })
  })
  raiz.tabs("select", Math.max(0, itens.findIndex((item) => item.atual)))
  raiz.data("pronta", true)
}

function clicarLink(evento) {
    const href = this.getAttribute("href")
    // Âncora dentro do trecho (as seções do glossário): rola até a seção na própria janela ou aba, sem tocar no endereço, que é o da casca.
    if (href?.startsWith("#") && href.length > 1) {
      evento.preventDefault()
      $(this).closest(".janela-corpo, .aba-raiz").find(`[id="${CSS.escape(href.slice(1))}"]`).get(0)?.scrollIntoView({ block: "start" })
      return
    }
    const reg = regDe(this)
    if (!reg || !href.startsWith("/") || this.target || this.hasAttribute("download") || evento.ctrlKey || evento.metaKey) return
    evento.preventDefault()
    this.closest("[popover]")?.hidePopover?.()
    // "Distribuir estes clientes" (14, R316): leva o filtro que está na grade agora, não o de quando a aba abriu.
    if (this.hasAttribute("data-com-filtros")) {
      const filtros = $(this).closest(".lista").find("form.filtros-da-grade").serializeArray().filter((campo) => campo.value !== "")
      return abrirEndereco(`${href.split("?")[0]}${filtros.length ? `?${$.param(filtros)}` : ""}`, reg)
    }
    // Diálogo aberto de dentro de uma janela (tratar a divergência): no fim, a janela se refaz junto com a aba.
    const janela = $(this).closest(".janela-corpo")
    if (this.hasAttribute("data-spa-dialogo") && janela.length) {
      return abrirDialogo(href, reg, { depois: (evento) => { recarregarJanela(janela); if (evento.atualizar) abas.atualizar(reg) } })
    }
    if (this.hasAttribute("data-spa-dialogo")) return abrirDialogo(href, reg)
    // "Descartar" da conferência do impacto: volta ao enquadramento na mesma aba.
    if (this.hasAttribute("data-mesma-aba")) return abas.navegar(reg, href)
    if (this.hasAttribute("data-spa-no-detalhe")) return abrirNoDetalhe(this)
    // Filtro e página da linha do tempo e das listas: troca só o cartão ou o resultado (`data-trecho`, com o destino em `data-trecho-alvo`).
    if (this.dataset.trecho) {
      const cartao = $(this).closest(this.dataset.trechoAlvo)
      if (!cartao.length) return abrirEndereco(href, reg)
      // Paginação das listas do servidor (o trecho `#resultado`): o mesmo caminho dos filtros, com a espera à vista e o endereço da aba.
      if (cartao.is('[id="resultado"]')) { abas.anotarEndereco(reg, href); return refazerResultado($(this).closest(".aba-raiz"), this.dataset.trecho) }
      return $.ajax({ url: this.dataset.trecho, dataType: "html", headers: { "X-CRM-Fragmento": "1" } }).done((html) => { const novo = $(html); cartao.replaceWith(novo); montar(novo) })
    }
    abrirEndereco(href, reg)
}

// Cliques dentro do detalhe de uma linha da grade: a extensão `datagrid-detailview` para o clique no detalhe (para a linha não ser escolhida) e
// desliga, a cada desenho da grade, o que se liga nele. Por isso eles são tratados na captura, na raiz das abas, antes de a extensão parar o clique.
function cliqueNoDetalhe(evento) {
  const alvo = evento.target
  if (!(alvo instanceof Element) || !alvo.closest(".datagrid-row-detail")) return
  const fechar = alvo.closest("[data-spa-fechar]")
  if (fechar) return fecharDetalhe($(fechar).closest(".datagrid-row-detail"))
  const popover = alvo.closest("[data-spa-popover]")
  if (popover) return abrirPopover(popover)
  const link = alvo.closest("a[href]")
  if (link) clicarLink.call(link, evento)
}

export function ligarNavegacao() {
  $(document).on("spa:abas-internas", "[data-abas]", function (evento) {
    evento.stopPropagation()
    montarAbasInternas(this)
  })

  $("#abas").on("click", "a[href]", clicarLink)
  $("#abas").on("click", "[data-spa-popover]", function () { abrirPopover(this) })
  $("#abas").on("click", "[data-alternar-detalhe], [data-alternar-todos]", function () { alternarDetalhe(this) })
  document.getElementById("abas").addEventListener("click", cliqueNoDetalhe, true)

  $("#abas").on("input", ".datagrid-row-detail form", function () { $(this).closest(".aba-raiz").trigger("inline:mudou") })
  // Formulário da própria aba (perfil, editor de segmentos, dados do credor): o que se digita é rascunho da aba, que pede confirmação ao fechar.
  $("#abas").on("input change", ".aba-raiz form:not(.filtros, .filtros-da-grade, .inline-editando, .dialogo)", function () { $(this).closest(".aba-raiz").trigger("inline:mudou") })
  $("#abas").on("submit", ".datagrid-row-detail form.dialogo", function (evento) {
    evento.preventDefault()
    enviar($(this), regDe(this), null)
  })

  // Formulário com cálculo à vista (simulação de acordo): o "Criar proposta" grava como um diálogo.
  $("#abas").on("submit", ".aba-raiz form[data-calculo]:not(.dialogo)", function (evento) {
    evento.preventDefault()
    enviar($(this), regDe(this), null)
  })

  // "Conferir" do editor de segmentos: o texto vai ao servidor sem gravar, e a resposta (o "Contando…", trecho vivo que o WebSocket completa) toma o lugar do
  // resultado anterior. Pedido novo cancela o anterior; a falha aparece no lugar, com "Tentar de novo".
  $("#abas").on("click", "[data-spa-conferir]", function () {
    const botao = $(this)
    const form = botao.closest("form")
    const alvo = () => form.find("[data-conferir]").first()
    form.data("conferir")?.abort()
    botao.prop("disabled", true).addClass("carregando")
    alvo().html('<p><span class="girando" aria-hidden="true"></span> Enviando o texto para contar…</p>')
    const pedido = $.ajax({ url: botao.data("spa-conferir"), method: "POST", data: semMetodo(form), dataType: "html" })
    form.data("conferir", pedido)
    acompanhar(alvo(), pedido)
    pedido
      .done((html) => {
        if (form.data("conferir") !== pedido) return
        const novo = $("<div>").html(html).children()
        alvo().replaceWith(novo)
        montar(novo)
        conferirVivos(novo)
      })
      .fail((xhr, estado) => {
        if (estado === "abort" || form.data("conferir") !== pedido) return
        falhaNoLugar(alvo(), mensagemDeFalha(xhr, "conferir"), () => botao.trigger("click"))
      })
      .always(() => { if (form.data("conferir") === pedido) botao.prop("disabled", false).removeClass("carregando") })
  })

  // Campos dependentes num formulário da própria aba (nova integração): o mesmo pedido do diálogo, que troca só o bloco que depende da escolha.
  $("#abas").on("spa:mudou", ".aba-raiz form:not(.dialogo)", function (evento, dependentes) {
    dependentes ||= $(evento.target).closest("[data-spa-dependentes]").data("spa-dependentes")
    if (!dependentes) return
    regDe(this).sujo = true
    refazerDependentes($(this), dependentes)
  })

  // Formulários soltos no trecho (`button_to`): gravam como um diálogo, sem trocar de página. Numa janela, quem se refaz é a janela.
  $("#abas").on("submit", ".aba-raiz form:not(.filtros-da-grade, .filtros, .dialogo, .inline-editando, [data-calculo])", function (evento) {
    evento.preventDefault()
    const janela = $(this).closest(".janela-corpo")
    enviar($(this), regDe(this), null, janela.length ? { depois: () => recarregarJanela(janela) } : {})
  })
}
