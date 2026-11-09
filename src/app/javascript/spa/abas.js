// Abas da aplicação (padrões de interface, revisão 38, P27): uma por item do menu e uma por registro de trabalho, vivas ao alternar, com o endereço no hash. Os registros guardam a raiz da aba.
import { esc } from "spa/formatos"
import { carregar, refazerVivo, tituloDe } from "spa/trecho"
import { redimensionar } from "spa/montagem"
import { assinarAba, soltarAba } from "spa/tempo-real"

const $ = window.jQuery

const LIMITE = 12
const MEMORIA = "crm-abas"
const abas = new Map()
let ordem = 0
let aoSelecionar = () => {}
const $abas = () => $("#abas")

export const chaveDe = (url) => url.split("?")[0]
const indiceDe = (reg) => $abas().tabs("getTabIndex", reg.painel)
const regDe = (painel) => [...abas.values()].find((reg) => reg.painel[0] === painel[0])
export const regDaRaiz = (raiz) => [...abas.values()].find((reg) => reg.raiz[0] === raiz[0])

let pedidoEmEspera = null

function guardar() {
  const lista = [...abas.values()].filter((reg) => reg.fechavel).map(({ url, titulo }) => ({ url, titulo }))
  try { sessionStorage.setItem(MEMORIA, JSON.stringify(lista)) } catch { /* memória opcional */ }
}

// Aba em segundo plano: o indicador enquanto espera, e a marca de falha até a pessoa voltar a ela (design system, 7.2).
function mostrarTitulo(reg) {
  const texto = esc(reg.titulo)
  const visivel = reg.painel.is(":visible")
  let titulo = texto
  if (reg.esperas > 0 && !visivel) titulo = `<span class="girando" aria-label="Em andamento"></span> ${texto}`
  else if (reg.falhou) titulo = `<span class="marca-de-falha" aria-label="Falhou">!</span> ${texto}`
  $abas().tabs("update", { tab: reg.painel, type: "header", options: { title: titulo } })
}

function carregarAba(reg) {
  reg.pendente = false
  reg.recarregadaEm = Date.now()
  reg.desatualizada = false
  carregar(reg.conteudo, reg.url, {
    depois: () => {
      assinarAba(reg, reg.conteudo.find("template.canais-do-trecho").data("canais") || [], () => avisarMudanca(reg))
      const titulo = tituloDe(reg.conteudo)
      if (titulo && titulo !== reg.titulo) { reg.titulo = titulo; mostrarTitulo(reg); guardar() }
    },
  })
}

function escreverEndereco(reg) {
  const hash = `#${reg.url}`
  if (window.location.hash !== hash) window.history.replaceState(null, "", hash)
}

// Todas as abas com trabalho: a pessoa escolhe qual fechar, e a aba pedida abre depois (padrões de interface, revisão 38, P27).
function perguntarQualFechar(url, opcoes) {
  const lista = $('<div class="escolha-de-aba"><p>Todas as abas abertas têm trabalho por salvar. Escolha qual fechar para abrir a nova.</p></div>')
  const candidatas = [...abas.values()].filter((reg) => reg.fechavel)
  candidatas.forEach((reg, indice) => {
    const rotulo = $('<label><input type="radio" name="aba-para-fechar"> <span></span></label>')
    rotulo.find("input").val(reg.chave).prop("checked", indice === 0)
    rotulo.find("span").text(reg.titulo)
    lista.append(rotulo)
  })
  lista.appendTo("body").dialog({
    title: "Limite de abas", modal: true, width: 420, closed: false, collapsible: false, minimizable: false, maximizable: false, resizable: false,
    buttons: [
      { text: "Continuar", handler() {
        const escolhida = abas.get(lista.find("input:checked").val())
        lista.dialog("close")
        if (!escolhida) return
        pedidoEmEspera = { url, opcoes }
        $abas().tabs("close", indiceDe(escolhida))
      } },
      { text: "Voltar", handler() { lista.dialog("close") } },
    ],
    onClose() { $(this).dialog("destroy") },
  })
  lista.dialog("dialog").find(".dialog-button a").first().addClass("c-marca")
}

function liberarVaga(url, opcoes) {
  if (abas.size < LIMITE) return true
  const livre = [...abas.values()].filter((reg) => !reg.sujo && !reg.gravando && reg.fechavel).sort((a, b) => a.uso - b.uso)[0]
  if (!livre) {
    perguntarQualFechar(url, opcoes)
    return false
  }
  $abas().tabs("close", indiceDe(livre))
  return true
}

export function abrir(url, opcoes = {}) {
  const { titulo = "Carregando…", fechavel = true, adiar = false, recarregar: refazer = false } = opcoes
  const existente = abas.get(chaveDe(url))
  if (existente) {
    $abas().tabs("select", indiceDe(existente))
    if (existente.url !== url) navegar(existente, url)
    // O fim de uma ação que leva a uma aba já aberta no mesmo endereço (a senha temporária, o segredo gerado): ela se refaz, para mostrar o resultado.
    else if (refazer) { existente.sujo = false; recarregar(existente) }
    return existente
  }
  if (!liberarVaga(url, opcoes)) return null
  $abas().tabs("add", { title: esc(titulo), closable: fechavel, selected: !adiar, content: '<div class="aba-raiz"><div class="aba-conteudo"></div></div>' })
  const painel = $abas().tabs("getTab", $abas().tabs("tabs").length - 1)
  const raiz = painel.find(".aba-raiz").first()
  const reg = { chave: chaveDe(url), url, titulo, painel, raiz, conteudo: raiz.children(".aba-conteudo"), fechavel, sujo: false, gravando: 0, esperas: 0, janelas: new Map(), pendente: true, uso: ++ordem }
  abas.set(reg.chave, reg)
  raiz.on("espera:mudou", (_evento, delta) => { reg.esperas += delta; mostrarTitulo(reg) })
  raiz.on("inline:mudou", () => { reg.sujo = true })
  // Gravação fora de diálogo (edição inline, formulário no detalhe da linha) que muda mais do que o próprio valor: a aba se refaz.
  raiz.on("spa:recarregar", () => { reg.sujo = false; recarregar(reg) })
  raiz.on("inline:fechou", () => {
    reg.sujo = raiz.find("form.inline-editando").length > 0
    if (!reg.sujo && reg.conteudo.find(".dado-mudou").length) atualizar(reg)
  })
  raiz.on("espera:falhou", () => { if (!reg.painel.is(":visible")) { reg.falhou = true; mostrarTitulo(reg) } })
  if (!adiar) { carregarAba(reg); aoSelecionar(reg); escreverEndereco(reg) }
  guardar()
  return reg
}

// Evento do tempo real numa tela desta aba. Visível: a lista recarrega a grade, as outras telas se refazem, com janelas e diálogos intactos (ficam na raiz da aba).
// Edição inline aberta: só o aviso. Escondida: fica marcada e se refaz ao ser escolhida. Uma rajada logo depois de a própria aba se refazer (a gravação dela) não repete.
function avisarMudanca(reg) {
  const passou = Date.now() - (reg.recarregadaEm || 0)
  if (passou < 1500) {
    // Trecho que se refaz sem piscar (lista, andamento da importação): o último evento da rajada não se perde; ele vale no fim da janela.
    const quieto = reg.conteudo.find("[data-spa-vivo], form.filtros, .lista .datagrid-f").length > 0
    if (quieto && !reg.relogioDoEvento) reg.relogioDoEvento = setTimeout(() => { reg.relogioDoEvento = null; avisarMudanca(reg) }, 1500 - passou)
    return
  }
  if (!reg.painel.is(":visible")) { reg.desatualizada = true; return }
  atualizar(reg)
}

export function atualizar(reg) {
  if (reg.conteudo.find("form.inline-editando").length) {
    if (!reg.conteudo.find(".dado-mudou").length) {
      $('<p class="dado-mudou" role="status">Os dados desta tela mudaram. Ela se atualiza quando você salvar ou descartar a edição aberta.</p>').prependTo(reg.conteudo)
    }
    return
  }
  reg.recarregadaEm = Date.now()
  reg.desatualizada = false
  const listas = reg.conteudo.find(".lista .datagrid-f")
  if (listas.length) { listas.datagrid("reload"); return }
  // Lista das páginas do servidor: só o trecho do resultado, com o filtro do endereço da aba (`spa/lista`).
  if (reg.conteudo.find("form.filtros").length && reg.conteudo.find('[id="resultado"]').length) { reg.raiz.trigger("spa:refazer-lista", [reg.url]); return }
  // Trecho vivo (andamento da importação): só ele, sem piscar a aba.
  const vivos = reg.conteudo.find("[data-spa-vivo]")
  if (vivos.length) { vivos.each(function () { refazerVivo($(this)) }); return }
  // Formulário da aba com algo digitado (o editor de segmentos, um perfil): refazer a aba apagaria o rascunho; fica o aviso, e ela se refaz quando gravar.
  if (reg.sujo) {
    if (!reg.conteudo.find(".dado-mudou").length) {
      $('<p class="dado-mudou" role="status">Os dados desta tela mudaram. O que você escreveu continua aqui; a tela se atualiza quando você salvar.</p>').prependTo(reg.conteudo)
    }
    return
  }
  carregarAba(reg)
}

export const atualizarTodas = () => abas.forEach((reg) => avisarMudanca(Object.assign(reg, { recarregadaEm: 0 })))

// A aba vai para outro endereço. Com outra chave (a conferência do impacto que volta ao enquadramento), a aba passa a ser a desse endereço; se ele já está
// aberto noutra aba, esta fecha e a outra se refaz (depois da gravação em andamento terminar, que segura o fechamento).
export function navegar(reg, url) {
  const chave = chaveDe(url)
  if (reg.chave !== chave) {
    const outra = abas.get(chave)
    if (outra) {
      $abas().tabs("select", indiceDe(outra))
      outra.url = url
      carregarAba(outra)
      escreverEndereco(outra)
      setTimeout(() => { reg.sujo = false; $abas().tabs("close", indiceDe(reg)) })
      return
    }
    abas.delete(reg.chave)
    reg.chave = chave
    abas.set(chave, reg)
  }
  reg.url = url
  carregarAba(reg)
  escreverEndereco(reg)
  guardar()
}

export const recarregar = (reg) => carregarAba(reg)

// Troca o endereço da aba sem recarregar (aba interna da ficha).
export function anotarEndereco(reg, url) {
  reg.url = url
  escreverEndereco(reg)
  guardar()
}

export function montarAbas({ selecionou }) {
  aoSelecionar = selecionou
  $abas().tabs({
    fit: true, border: false,
    onSelect(_titulo, indice) {
      const painel = $abas().tabs("getTab", indice)
      const reg = painel && regDe(painel)
      if (!reg) return
      reg.uso = ++ordem
      reg.falhou = false
      if (reg.pendente) carregarAba(reg)
      else if (reg.desatualizada) atualizar(reg)
      escreverEndereco(reg)
      selecionou(reg)
      mostrarTitulo(reg)
      redimensionar(painel)
    },
    onBeforeClose(_titulo, indice) {
      const reg = regDe($abas().tabs("getTab", indice))
      if (!reg) return true
      if (reg.gravando) {
        $.messager.alert("Gravação em andamento", "Espere a resposta do servidor para fechar esta aba.", "info")
        return false
      }
      if (!reg.sujo) return true
      confirmarDescarte(() => { reg.sujo = false; $abas().tabs("close", indiceDe(reg)) })
      return false
    },
    onClose() {
      const vivos = new Set($abas().tabs("tabs").map((painel) => painel[0]))
      for (const [chave, reg] of abas) if (!vivos.has(reg.painel[0])) { soltarAba(reg); abas.delete(chave) }
      guardar()
      if (pedidoEmEspera && abas.size < LIMITE) {
        const { url, opcoes } = pedidoEmEspera
        pedidoEmEspera = null
        abrir(url, opcoes)
      }
    },
  })
}

export function confirmarDescarte(depois) {
  const antes = { ok: $.messager.defaults.ok, cancel: $.messager.defaults.cancel }
  Object.assign($.messager.defaults, { ok: "Descartar", cancel: "Voltar" })
  $.messager.confirm("Descartar o que foi escrito?", "Há um formulário a meio. Ao fechar, o que foi escrito se perde.", (sim) => { if (sim) depois() })
  Object.assign($.messager.defaults, antes)
}

export const regAtual = () => regDe($abas().tabs("getSelected"))

export function abasGuardadas() {
  try { return JSON.parse(sessionStorage.getItem(MEMORIA)) || [] } catch { return [] }
}
