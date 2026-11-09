// A casca da SPA (decisão 0028): leiaute, menu, abas, entrada e sessão.
import { ligarVitrine } from "spa/vitrine"
import * as abas from "spa/abas"
import { configurar } from "spa/espera"
import { esc } from "spa/formatos"
import { abrir as abrirDialogo, enviar } from "spa/dialogos"
import { abrir as abrirJanela } from "spa/janelas"
import { definirJanelas, ehJanela, ligarNavegacao } from "spa/navegacao"
import { assinar } from "spa/tempo-real"
import { carregar } from "spa/trecho"
import "spa/lista"

const $ = window.jQuery

const ICONES = { Geral: "icon-sum", "Cobrança": "icon-tip", Financeiro: "icon-filter", "Entrada de dados": "icon-save", "Distribuição": "icon-reload", "Administração": "icon-lock" }
const LARGURA_DO_MENU = 212
const LARGURA_RECOLHIDO = 60
let sincronizando = false
let cascaMontada = false

const itemDoMenu = ({ rotulo, caminho, contador, subitens }) => ({
  ...(caminho ? { id: caminho } : {}),
  text: esc(rotulo) + (contador ? ` <span class="selo-menu">${esc(contador)}</span>` : ""),
  rotulo,
  ...(subitens ? { children: subitens.map(itemDoMenu) } : {}),
})

function destacarMenu(reg) {
  sincronizando = true
  $("#menu .sidemenu-tree").each(function () {
    const arvore = $(this)
    arvore.find(".tree-node-selected").removeClass("tree-node-selected")
    const no = arvore.tree("find", reg.chave)
    if (no) arvore.tree("select", no.target)
  })
  sincronizando = false
}

function montarMenu(grupos) {
  const dados = grupos.map(({ titulo, itens }, indice) => ({ text: esc(titulo), iconCls: ICONES[titulo] || "icon-more", state: indice === 0 ? "open" : undefined, children: itens.map(itemDoMenu) }))
  $("#menu").sidemenu({
    data: dados, width: LARGURA_DO_MENU - 2, border: false, multiple: false, floatMenuWidth: 220,
    onSelect(item) { if (!sincronizando && item.id) abas.abrir(item.id, { titulo: item.rotulo }) },
  })
}

function montarRecolher(oeste) {
  let recolhido = false
  const recolher = (sim) => {
    recolhido = sim
    $("#menu").sidemenu(sim ? "collapse" : "expand").sidemenu("resize", { width: sim ? LARGURA_RECOLHIDO - 2 : LARGURA_DO_MENU - 2 })
    oeste.panel("resize", { width: sim ? LARGURA_RECOLHIDO : LARGURA_DO_MENU })
    $("#app").layout("resize")
    try { localStorage.setItem("crm-menu-recolhido", sim ? "1" : "0") } catch { /* preferência opcional */ }
  }
  $("#alternar-menu").on("click", () => recolher(!recolhido))
  let guardado = null
  try { guardado = localStorage.getItem("crm-menu-recolhido") } catch { /* preferência opcional */ }
  if (guardado === "1" || (guardado === null && window.innerWidth < 1280)) recolher(true)
}

function sair() {
  $.ajax({ url: "/sessao", method: "POST", data: { _method: "delete" } }).always(() => {
    try { sessionStorage.removeItem("crm-abas") } catch { /* memória opcional */ }
    window.location.replace(window.location.pathname)
  })
}

function montarCasca(menu) {
  const app = $("#app").prop("hidden", false)
  app.layout({ fit: true })
  app.layout("panel", "north").panel("resize", { height: $("#norte").children().toArray().reduce((soma, filho) => soma + $(filho).outerHeight(), 0) })
  const oeste = app.layout("panel", "west")
  oeste.panel("resize", { width: LARGURA_DO_MENU })
  app.layout("resize")
  montarMenu(menu.grupos)
  abas.montarAbas({ selecionou: destacarMenu })
  ligarNavegacao()
  montarRecolher(oeste)
  if (!menu.busca) $("#busca-global").remove()
  else $("#busca-global").searchbox({ prompt: "Buscar cliente por nome ou documento", width: 320, searcher(texto) { if (texto) abas.abrir(`/clientes?busca=${encodeURIComponent(texto)}`, { titulo: "Clientes" }) } })
  $("#menu-usuario").prop("hidden", false).menu({ onClick(item) { if (item.id === "m-sair") sair(); else abrirDialogo("/senha/editar", abas.regAtual(), { depois: () => {} }) } })
  $("#sino").on("click", () => abrirJanela("/avisos", abas.regAtual()))
  $(document).on("cable:notice-created spa:janela-gravou", () => atualizarMenu())
  $("#usuario").on("click", function () { const lugar = $(this).offset(); $("#menu-usuario").menu("show", { left: lugar.left, top: lugar.top + 38 }) })
  cascaMontada = true
}

function mostrarUsuario(menu) {
  if (!menu.trocar_senha) { const item = $("#menu-usuario").menu("findItem", "Trocar a senha"); if (item) $("#menu-usuario").menu("hideItem", item.target) }
  $("#usuario").text(`${menu.usuario.nome} ▾`).attr("title", menu.usuario.nome)
  // 14, R324: a operação do usuário de operação, no cabeçalho.
  $("#operacao-atual").text(menu.usuario.operacao || "").attr("title", menu.usuario.operacao_razao_social || "").prop("hidden", !menu.usuario.operacao)
  $("#sino .contador").text(menu.avisos).prop("hidden", !menu.avisos)
  $("#sino").attr("aria-label", menu.avisos ? `Avisos, ${menu.avisos} não lidos` : "Avisos, nenhum não lido")
}

// Contadores do menu (Divergências, Promessas e Acordos pendentes): o texto de cada folha se refaz em cada árvore do `sidemenu`.
function atualizarContadores(menu) {
  const folhas = new Map()
  const juntar = (itens) => itens.forEach((item) => { if (item.caminho) folhas.set(item.caminho, item); if (item.subitens) juntar(item.subitens) })
  menu.grupos.forEach((grupo) => juntar(grupo.itens))
  $("#menu .sidemenu-tree").each(function () {
    const arvore = $(this)
    folhas.forEach((item, caminho) => {
      const no = arvore.tree("find", caminho)
      if (no) arvore.tree("update", { target: no.target, text: itemDoMenu(item).text })
    })
  })
}

function atualizarMenu() {
  return $.ajax({ url: "/menu.json", dataType: "json" }).done((menu) => { mostrarUsuario(menu); atualizarContadores(menu) })
}

function abrirAbasIniciais() {
  // Lê o endereço e a memória antes de abrir o Resumo, que escreve os dois.
  const ativa = window.location.hash.slice(1)
  const guardadas = abas.abasGuardadas()
  abas.abrir("/resumo", { titulo: "Resumo", fechavel: false })
  guardadas.forEach(({ url, titulo }) => abas.abrir(url, { titulo, adiar: true }))
  abrirEndereco(ativa)
}

// Endereço vindo de fora (link de uma página antiga, hash digitado): o detalhe de consulta abre em janela sobre a aba escolhida; o resto, em aba.
function abrirEndereco(url) {
  if (!url || url === "/resumo") return
  if (ehJanela(url)) abrirJanela(url, abas.regAtual())
  else abas.abrir(url)
}

function carregarMenu() {
  return $.ajax({ url: "/menu.json", dataType: "json" }).done((menu) => {
    $("#entrada").prop("hidden", true)
    const primeira = !cascaMontada
    definirJanelas(menu.janelas)
    if (primeira) montarCasca(menu)
    assinar(menu.canais, { reconectou: abas.atualizarTodas })
    mostrarUsuario(menu)
    if (menu.aviso) $.messager.show({ title: menu.tom === "danger" ? "Atenção" : "Feito", msg: esc(menu.aviso), timeout: 6000, showType: "slide" })
    if (primeira) abrirAbasIniciais()
  })
}

function mostrarEntrada(texto) {
  if (texto) $("#entrada-mensagem").text(texto)
  $("#definir-senha").prop("hidden", true)
  $("#entrada-form").prop("hidden", false)
  $("#entrada").prop("hidden", false)
  $("#entrada-email").trigger("focus")
}

// Senha temporária (02, R38): o servidor responde 409 a tudo até a senha ser definida. O formulário vem do Rails e grava como um diálogo.
function mostrarDefinirSenha() {
  const caixa = $("#definir-senha").prop("hidden", false)
  $("#entrada-form").prop("hidden", true)
  $("#entrada").prop("hidden", false)
  const conteudo = caixa.find(".definir-senha-conteudo")
  if (conteudo.data("carregando")) return
  conteudo.data("carregando", true)
  carregar(conteudo, "/senha/editar", {
    depois: () => {
      caixa.find(".definir-senha-titulo").text(conteudo.find("form.dialogo").data("titulo"))
      conteudo.removeData("carregando").find("input[type=password]").first().trigger("focus")
    },
  })
}

function ligarDefinirSenha() {
  const conteudo = $("#definir-senha .definir-senha-conteudo")
  const registro = { gravando: 0, sujo: false }
  conteudo.on("submit", "form.dialogo", function (evento) {
    evento.preventDefault()
    enviar($(this), registro, null, { depois: () => { conteudo.empty(); carregarMenu() } })
  })
  conteudo.on("click", "[data-spa-fechar]", sair)
}

function ligarEntrada() {
  $("#entrada-form").on("submit", function (evento) {
    evento.preventDefault()
    const botao = $("#entrada-botao").prop("disabled", true).addClass("carregando")
    $.ajax({ url: "/sessao", method: "POST", data: $(this).serialize(), dataType: "text" })
      .done(() => { $("#entrada-senha").val(""); carregarMenu() })
      .fail((xhr) => {
        // A recusa vem com a mensagem do servidor; o manipulador global não reabre a entrada, que já está aberta. Uma resposta que não é a recusa
        // (página de erro, proteção de origem) também termina à vista: a leitura não pode lançar, ou o botão ficaria girando (design system, 7.2).
        let mensagem = null
        try { mensagem = JSON.parse(xhr.responseText || "{}").erro } catch { mensagem = null }
        if (!mensagem) mensagem = xhr.status ? `O servidor recusou a entrada (erro ${xhr.status}). Recarregue a página e tente de novo.` : "Sem resposta do servidor. Confira a conexão e tente de novo."
        $("#entrada-mensagem").text(mensagem)
      })
      .always(() => botao.prop("disabled", false).removeClass("carregando"))
  })
}

export function partida() {
  ligarVitrine()
  $.parser.auto = false
  configurar({ sessaoVencida: () => mostrarEntrada(cascaMontada ? "A sessão terminou. Entre de novo para continuar; as abas continuam abertas." : null), senhaTemporaria: mostrarDefinirSenha })
  ligarEntrada()
  ligarDefinirSenha()
  $(window).on("hashchange", () => abrirEndereco(window.location.hash.slice(1)))
  carregarMenu()
}
