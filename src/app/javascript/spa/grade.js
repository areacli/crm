// Grades (`datagrid`): colunas com o formatter comum e, nas listas do servidor, o pedido novo cancela o anterior, e resposta atrasada é descartada (design system, 7.2).
import { FORMATTERS } from "spa/formatos"
import { mensagemDeFalha } from "spa/espera"

const $ = window.jQuery

const colunaDe = ({ campo, titulo, largura, tipo = "texto", ordena }) => ({
  field: campo, title: titulo, width: largura, sortable: Boolean(ordena), align: tipo === "numero" ? "right" : "left",
  formatter: FORMATTERS[tipo], ...(tipo === "acoes" ? { fixed: true, align: "center" } : {}),
})

const filtrosDe = (tabela) => {
  const form = tabela.closest(".lista").find("form.filtros-da-grade")
  return form.length ? Object.fromEntries(form.serializeArray().filter((c) => c.value !== "").map((c) => [c.name, c.value])) : {}
}

function falha(tabela, xhr) {
  const barra = $('<div class="falha-da-grade" role="alert"><span></span> <button type="button" data-variant="secondary">Tentar de novo</button></div>')
  barra.find("span").text(mensagemDeFalha(xhr, "carregar a lista"))
  barra.find("button").on("click", () => tabela.datagrid("reload"))
  tabela.closest(".grade").prevAll(".falha-da-grade").remove()
  barra.insertBefore(tabela.closest(".grade"))
  setTimeout(() => tabela.datagrid("resize"))
}

function loader(tabela, url) {
  return function (parametros, sucesso) {
    tabela.data("pedido")?.abort()
    if (tabela.closest(".grade").prevAll(".falha-da-grade").remove().length) setTimeout(() => tabela.datagrid("resize"))
    const dados = { ...filtrosDe(tabela), pagina: parametros.page, por_pagina: parametros.rows }
    if (parametros.sort) Object.assign(dados, { ordem: parametros.sort, direcao: parametros.order })
    const pedido = $.ajax({ url, data: dados, dataType: "json" })
    tabela.data("pedido", pedido)
    pedido.done((resposta) => {
      if (tabela.data("pedido") !== pedido) return
      sucesso(resposta)
      // Nota (o filtro ativo) e aviso (a consulta passou do limite) que o servidor manda junto com a página: acima da grade, que refaz a altura
      // para a barra de páginas continuar à vista.
      const caixa = tabela.closest(".grade")
      const antes = caixa.prevAll(".nota-da-grade").remove().length
      if (resposta.nota) $('<p class="nota-da-grade" role="status"></p>').text(resposta.nota).insertBefore(caixa)
      if (resposta.aviso) $('<p class="nota-da-grade" data-tom="warning" role="status"></p>').text(resposta.aviso).insertBefore(caixa)
      if (antes || resposta.nota || resposta.aviso) setTimeout(() => tabela.datagrid("resize"))
    })
    pedido.fail((xhr, situacao) => {
      if (situacao === "abort" || tabela.data("pedido") !== pedido) return
      sucesso({ total: 0, rows: [] })
      if (xhr.status !== 401 && xhr.status !== 409) falha(tabela, xhr)
    })
  }
}

export function montarGrade(elemento) {
  const tabela = $(elemento)
  const opcoes = tabela.data("grade")
  const remota = Boolean(opcoes.url)
  // Valor nunca sai cortado: sem largura para todas as colunas, a grade rola na horizontal.
  const necessaria = opcoes.colunas.reduce((soma, coluna) => soma + (coluna.largura || 0), 0)
  const disponivel = tabela.closest(".grade").width()
  tabela.datagrid({
    fit: true, border: false, fitColumns: !disponivel || disponivel >= necessaria, singleSelect: true, striped: true, nowrap: true, remoteSort: remota,
    loadMsg: "Carregando…", emptyMsg: opcoes.vazio, columns: [opcoes.colunas.map(colunaDe)],
    pagination: remota, pageSize: 10, pageList: [10, 20, 50, 100], sortName: opcoes.ordem, sortOrder: opcoes.direcao,
    ...(remota ? { loader: loader(tabela, opcoes.url) } : { data: { total: opcoes.linhas.length, rows: opcoes.linhas } }),
  })
}

// Tabela da própria tela, escrita pelo Rails em HTML semântico (`data-numerico`, a seta e a faixa do detalhe do P26, `data-atual`): vira grade na montagem,
// e a view continua sem saber do EasyUI. As células já chegam escapadas pelo ERB e passam pelo formatter `html` como estão. O detalhe usa a extensão
// `datagrid-detailview`. Fica como está a tabela com campo de formulário, total no rodapé (`tfoot`), `rowspan` ou `colspan` fora da faixa do detalhe, ou com `data-sem-grade`.
const semSeta = (celula) => { const copia = $(celula).clone(); copia.find("[data-alternar-detalhe], [data-alternar-todos]").remove(); return copia }

// Texto longo numa célula (P26): pode sair cortado com reticências na linha, inteiro no `title`, para a grade caber sem rolar de lado.
const LONGO = 24
function conteudo(celula) {
  const copia = semSeta(celula)
  if (copia.children().length || copia.text().trim().length <= LONGO) return copia.html().trim()
  return $('<span class="cortado"></span>').attr("title", copia.text().trim()).text(copia.text().trim()).prop("outerHTML")
}
const MINIMA = 140

// O detalhe fica na parte visível da grade, mesmo quando ela rola de lado (`position: sticky` no CSS).
export const larguraDoDetalhe = (caixa) => Math.max(320, caixa.width() - 40)

export function transformarTabela(elemento) {
  const tabela = $(elemento)
  const corpo = tabela.children("tbody").children("tr")
  const linhas = corpo.not(".detalhe-da-linha")
  if (tabela.is("[data-sem-grade]") || tabela.children("tfoot").length || corpo.find("input:not([type=hidden]), select, textarea").length || linhas.children("[rowspan], [colspan]").length) return
  const caixa = tabela.closest(".tabela")
  const detalhes = new Map(corpo.filter(".detalhe-da-linha").map((_, tr) => [[tr.id, $(tr).children("td").html()]]).get())
  const colunas = tabela.children("thead").children("tr").first().children().map((i, th) => ({
    field: `c${i}`, title: semSeta(th).html().trim(), align: th.hasAttribute("data-numerico") ? "right" : "left", formatter: FORMATTERS.html,
  })).get()
  const rows = linhas.map((_, tr) => {
    const row = { _atual: tr.hasAttribute("data-atual") }
    $(tr).children().each((i, celula) => {
      const seta = $(celula).find("[data-alternar-detalhe]")
      if (seta.length) row._detalhe = detalhes.get(seta.attr("aria-controls"))
      // Ações da linha (botão direto e o menu "⋯") lado a lado, numa linha só.
      row[`c${i}`] = celula.hasAttribute("data-acoes") ? `<span class="acoes-da-linha">${semSeta(celula).html().trim()}</span>` : conteudo(celula)
    })
    return row
  }).get()
  // Coluna sem nada em nenhuma linha (a de ações, quando nenhuma linha tem ação) sai: não ocupa a largura que falta às outras.
  const vazias = colunas.filter((coluna) => rows.length && rows.every((row) => !row[coluna.field]))
  vazias.forEach((coluna) => colunas.splice(colunas.indexOf(coluna), 1))
  const legenda = tabela.children("caption").not(".apenas-leitor-de-tela")
  if (legenda.length) $('<p class="legenda-da-grade"></p>').html(legenda.html()).insertBefore(caixa)
  const nova = $("<table></table>")
  tabela.replaceWith(nova)
  // Sai a classe `tabela`: as regras dela (largura, bordas, espaçamento) pegariam as tabelas internas da grade.
  caixa.removeClass("tabela").addClass("tabela-em-grade").removeAttr("tabindex")
  const comDetalhe = rows.some((row) => row._detalhe)
  nova.datagrid({
    data: { total: rows.length, rows }, columns: [colunas], border: false, striped: true, nowrap: true, singleSelect: true, fitColumns: false,
    rowStyler: (_indice, row) => (row._atual ? { class: "linha-atual" } : ""),
    onBeforeSelect: () => false,
    // A grade tem altura pelo conteúdo: abrir ou fechar um detalhe refaz a altura.
    ...(comDetalhe ? { view: window.detailview, detailFormatter: (_indice, row) => (row._detalhe ? `<div class="detalhe-da-grade" style="width:${larguraDoDetalhe(caixa)}px">${row._detalhe}</div>` : ""), onExpandRow: () => nova.datagrid("resize"), onCollapseRow: () => nova.datagrid("resize") } : {}),
  })
  // Largura pelo conteúdo; se sobra espaço, as colunas se esticam até a borda. Valor nunca sai cortado: sem espaço, a grade rola na horizontal.
  nova.datagrid("autoSizeColumn")
  const opcao = (coluna) => nova.datagrid("getColumnOption", coluna.field)
  const elasticas = colunas.filter((coluna) => coluna.title.replace(/<[^>]*>/g, "").trim() && !/apenas-leitor-de-tela/.test(coluna.title))
  colunas.forEach((coluna) => { opcao(coluna).width += elasticas.includes(coluna) ? 4 : 2 })
  const corpo2 = nova.datagrid("getPanel").find(".datagrid-view2 .datagrid-body")
  const naturais = new Map(colunas.map((coluna) => [coluna.field, opcao(coluna).width]))
  // Como o redimensionamento do próprio datagrid: a largura da caixa acompanha a da coluna.
  const aplicar = () => {
    colunas.forEach((coluna) => { const o = opcao(coluna); o.boxWidth = o.width - o.deltaWidth; o.auto = undefined })
    nova.datagrid("fixColumnSize")
  }
  const cortaveis = colunas.filter((coluna) => rows.some((row) => /class="cortado"/.test(row[coluna.field])))
  // Reparte a largura do corpo a partir da largura natural de cada coluna. Roda na montagem e sempre que a caixa muda de largura (menu recolhido, janela, aba).
  const distribuir = () => {
    colunas.forEach((coluna) => { opcao(coluna).width = naturais.get(coluna.field) })
    // O espaço é o do corpo da grade (sem a coluna da seta), menos a borda de cada célula, que não entra na largura da coluna.
    const disponivel = corpo2.prop("clientWidth") - colunas.length - 1
    let necessaria = colunas.reduce((soma, coluna) => soma + opcao(coluna).width, 0)
    // Sem espaço: as colunas de texto cortado encolhem, a mais larga primeiro, até a grade caber; números e ações nunca encolhem.
    for (let excesso = necessaria - disponivel; excesso > 0;) {
      const maior = cortaveis.filter((coluna) => opcao(coluna).width > MINIMA).sort((a, b) => opcao(b).width - opcao(a).width)[0]
      if (!maior) break
      const corte = Math.min(excesso, opcao(maior).width - MINIMA, 40)
      opcao(maior).width -= corte
      excesso -= corte
      necessaria -= corte
    }
    if (disponivel > necessaria) {
      const base = elasticas.reduce((soma, coluna) => soma + opcao(coluna).width, 0)
      let sobra = disponivel - necessaria
      elasticas.forEach((coluna, i) => {
        const extra = i === elasticas.length - 1 ? sobra : Math.floor(((disponivel - necessaria) * opcao(coluna).width) / base)
        opcao(coluna).width += extra
        sobra -= extra
      })
    }
    aplicar()
    // Se ainda assim a grade esticada passou da borda, a última coluna elástica devolve o que sobrou.
    const passou = corpo2.prop("scrollWidth") - corpo2.prop("clientWidth")
    const ultima = elasticas[elasticas.length - 1]
    if (passou > 0 && disponivel > necessaria && ultima && opcao(ultima).width - passou > MINIMA / 2) { opcao(ultima).width -= passou; aplicar() }
    // O EasyUI decide a rolagem horizontal antes das larguras finais: sem isto, o que não coube some, sem barra. O `resize` refaz a decisão e a altura.
    nova.datagrid("resize")
  }
  distribuir()
  // A largura da caixa muda sem a grade saber: menu recolhido, janela, a coluna do lado.
  let largura = caixa.width()
  let espera
  new ResizeObserver(() => {
    clearTimeout(espera)
    espera = setTimeout(() => {
      const agora = caixa.width()
      if (!agora || agora === largura || !document.contains(nova[0])) return
      largura = agora
      nova.datagrid("resize", { width: agora })
      distribuir()
    }, 120)
  }).observe(caixa[0])
  if (!comDetalhe) return
  rows.forEach((row, indice) => { if (!row._detalhe) nova.datagrid("getExpander", indice).css("visibility", "hidden") })
  // A seta do cabeçalho abre ou fecha todos os detalhes (P26).
  const todas = $('<span class="datagrid-row-expander datagrid-row-expand" role="button" tabindex="0" aria-label="Mostrar os detalhes de todas as linhas" style="display:inline-block;width:16px;height:16px;margin-top:8px;cursor:pointer"></span>')
  nova.datagrid("getPanel").find(".datagrid-header-expander").append(todas)
  todas.on("click keydown", (evento) => {
    if (evento.type === "keydown" && evento.key !== "Enter" && evento.key !== " ") return
    evento.preventDefault()
    const abrir = todas.hasClass("datagrid-row-expand")
    todas.toggleClass("datagrid-row-expand", !abrir).toggleClass("datagrid-row-collapse", abrir)
    rows.forEach((row, indice) => { if (row._detalhe) nova.datagrid(abrir ? "expandRow" : "collapseRow", indice) })
  })
}

// Edição inline numa célula: a coluna alarga enquanto o campo está aberto e volta à largura dela ao fechar.
$(document).on("inline:celula", "[data-inline]", function (_evento, aberto) {
  const celula = $(this).closest("td[field]")
  const grade = celula.closest(".datagrid").find("table.datagrid-f").first()
  if (!celula.length || !grade.length) return
  const opcao = grade.datagrid("getColumnOption", celula.attr("field"))
  if (opcao._largura === undefined) opcao._largura = opcao.width
  const form = $(this).next("form.inline-editando")
  // O campo e os dois botões numa linha só; a mensagem de erro fica embaixo.
  const precisa = form.children(":not(.inline-erro)").get().reduce((soma, filho) => soma + filho.offsetWidth + 6, 24)
  opcao.width = aberto && form.length ? Math.max(opcao._largura, precisa) : opcao._largura
  opcao.boxWidth = opcao.width - opcao.deltaWidth
  grade.datagrid("fixColumnSize", celula.attr("field"))
  grade.datagrid("fixRowHeight")
  if (!aberto) grade.datagrid("getPanel").find(".datagrid-view2 .datagrid-body").scrollLeft(0)
})

// Busca e filtros da lista: 300 ms depois da última tecla, como nas páginas do servidor.
let relogio = null
$(document).on("input spa:mudou", "form.filtros-da-grade", function () {
  const tabela = $(this).closest(".lista").find(".datagrid-f")
  clearTimeout(relogio)
  relogio = setTimeout(() => tabela.datagrid("load"), 300)
})
$(document).on("submit", "form.filtros-da-grade", (evento) => evento.preventDefault())
