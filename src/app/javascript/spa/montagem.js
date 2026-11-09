// Monta os componentes de um trecho recém-chegado. É o único lugar que liga marcação do Rails a plugin do EasyUI; nenhuma view chama plugin (plano, seção 4).
import { montarGrade, transformarTabela } from "spa/grade"
import { montarCalculos } from "spa/calculo"
import { aplicarLimites, montarDeslizantes } from "spa/deslizantes"
import "spa/inline"

const $ = window.jQuery

// As listas de escolha viram `combobox`. O `id` passa ao campo visível, para o rótulo continuar ligado a ele.
function montarEscolhas(alvo) {
  // Só o que ainda não foi montado: um trecho refeito dentro da aba não remonta os campos que já estão nela.
  alvo.find("select:not([multiple]):not(.combobox-f)").each(function () {
    const escolha = $(this)
    const id = escolha.attr("id")
    const dependentes = escolha.data("spa-dependentes")
    // Com o `required` no campo escondido, o navegador recusa o envio sem dizer nada. Quem responde é o servidor, com o erro no diálogo; o `required` do `combobox` não serve,
    // porque ele confere o texto visível, e "Escolha o canal" conta como preenchido.
    // Como o navegador: sem `selected`, vale a primeira opção.
    const valor = escolha.val()
    // O Rails põe uma opção vazia, sem texto, na lista obrigatória sem `include_blank`: ela sai da lista, e o campo ainda sem escolha mostra "Escolha".
    const vazia = escolha.children("option").filter((_, opcao) => opcao.value === "" && !opcao.textContent.trim()).remove()
    escolha.removeAttr("id required").combobox({
      value: valor, ...(vazia.length ? { prompt: "Escolha" } : {}), editable: false, panelHeight: "auto", panelMaxHeight: 260, width: "100%", validateOnCreate: false,
      // O evento sai do próprio campo e sobe até o formulário: quem ouve sabe de onde veio (o bloco de campos dependentes dele).
      onChange() { escolha.trigger("spa:mudou", [dependentes]) },
    })
    if (id) escolha.combobox("textbox").attr("id", id)
  })
}

// Datas em dd/mm/aaaa (o idioma pt_BR do EasyUI não define o formato). O campo visível é o `datebox`; o que vai ao servidor continua em aaaa-mm-dd, num
// campo escondido com o nome original.
const doisDigitos = (n) => String(n).padStart(2, "0")
const DATAS = {
  formatter: (d) => `${doisDigitos(d.getDate())}/${doisDigitos(d.getMonth() + 1)}/${d.getFullYear()}`,
  parser: (texto) => {
    const partes = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto || "")
    return partes ? new Date(+partes[3], +partes[2] - 1, +partes[1]) : new Date()
  },
}
// Data e hora (`datetime-local`): dd/mm/aaaa hh:mm na tela, aaaa-mm-ddThh:mm no campo escondido.
const DATAS_E_HORAS = {
  formatter: (d) => `${DATAS.formatter(d)} ${doisDigitos(d.getHours())}:${doisDigitos(d.getMinutes())}`,
  parser: (texto) => {
    const partes = /^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2})/.exec(texto || "")
    return partes ? new Date(+partes[3], +partes[2] - 1, +partes[1], +partes[4], +partes[5]) : new Date()
  },
}
const horaParaIso = (texto) => { const p = /^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2})/.exec(texto || ""); return p ? `${p[3]}-${p[2]}-${p[1]}T${p[4]}:${p[5]}` : "" }
const horaDeIso = (iso) => { const p = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || ""); return p ? `${p[3]}/${p[2]}/${p[1]} ${p[4]}:${p[5]}` : "" }
const paraIso = (texto) => { const partes = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto || ""); return partes ? `${partes[3]}-${partes[2]}-${partes[1]}` : "" }
const deIso = (iso) => { const partes = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || ""); return partes ? `${partes[3]}/${partes[2]}/${partes[1]}` : "" }

// O `datebox` só aceita a data que vem do calendário: a digitada no campo fica no texto, sem virar valor. Ao sair do campo ou no Enter, o texto
// completo e válido vira o valor (e o `onChange` grava o campo escondido).
function aceitarDigitada(campo, plugin, formato) {
  const aceitar = (evento) => {
    if (evento.type === "keydown" && evento.key !== "Enter") return
    // No Enter, o próprio `datebox` troca o texto pela data do calendário: o texto é lido antes dele (na captura) e gravado depois, por cima.
    const texto = evento.target.value.trim()
    if (formato.test(texto)) setTimeout(() => { if (texto !== campo[plugin]("getValue")) campo[plugin]("setValue", texto) })
  }
  const caixa = campo[plugin]("textbox")[0]
  caixa.addEventListener("keydown", aceitar, true)
  caixa.addEventListener("blur", aceitar)
}

function montarDatas(alvo) {
  alvo.find('input[type="date"]').each(function () {
    const original = $(this)
    const id = original.attr("id")
    const escondido = $('<input type="hidden">').attr("name", original.attr("name")).val(original.val())
    const visivel = $('<input type="text">').insertAfter(original)
    original.replaceWith(escondido)
    visivel.datebox({
      ...DATAS, width: "100%", height: 30, value: deIso(escondido.val()), validateOnCreate: false, editable: true, currentText: "Hoje", closeText: "Fechar",
      onChange(texto) { escondido.val(paraIso(texto)); escondido.trigger("spa:mudou") },
    })
    if (id) visivel.datebox("textbox").attr("id", id)
    aceitarDigitada(visivel, "datebox", /^\d{2}\/\d{2}\/\d{4}$/)
  })
  alvo.find('input[type="datetime-local"]').each(function () {
    const original = $(this)
    const id = original.attr("id")
    const escondido = $('<input type="hidden">').attr("name", original.attr("name")).val(original.val())
    const visivel = $('<input type="text">').insertAfter(original)
    original.replaceWith(escondido)
    visivel.datetimebox({
      ...DATAS_E_HORAS, width: "100%", height: 30, value: horaDeIso(escondido.val()), validateOnCreate: false, editable: true, showSeconds: false,
      currentText: "Agora", closeText: "Fechar", okText: "Escolher",
      onChange(texto) { escondido.val(horaParaIso(texto)); escondido.trigger("spa:mudou") },
    })
    if (id) visivel.datetimebox("textbox").attr("id", id)
    aceitarDigitada(visivel, "datetimebox", /^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}$/)
  })
}

// Campos que só valem para uma escolha (`data-mostrar-se-campo` e `data-mostrar-se-valor`, com "!" para "menos este"): somem, e os campos deles ficam
// desligados, para não irem ao servidor.
function aplicarCondicionais(form) {
  form.find("[data-mostrar-se-campo]").each(function () {
    const bloco = $(this)
    // Botões de opção: vale o marcado.
    const campos = form.find(`[name="${bloco.data("mostrar-se-campo")}"]`)
    const atual = campos.is(":radio") ? campos.filter(":checked").val() : campos.val()
    const esperado = String(bloco.data("mostrar-se-valor"))
    const mostrar = esperado.startsWith("!") ? atual !== esperado.slice(1) : atual === esperado
    bloco.toggle(mostrar).find("input, select, textarea").prop("disabled", !mostrar)
  })
}
$(document).on("spa:mudou", "form", function () { aplicarCondicionais($(this)) })
$(document).on("change", "form input[type=radio]", function () { aplicarCondicionais($(this).closest("form")) })
// Caixa de marcar dentro de um bloco de campos dependentes (os títulos da promessa): também pede ao servidor o que depende dela.
$(document).on("change", "form [data-spa-dependentes] input[type=checkbox], form [data-spa-dependentes] input[type=radio]", function () { $(this).trigger("spa:mudou") })

// Campo de arquivo: o `filebox` do EasyUI, com o botão em português; o arquivo continua num `input type=file` com o nome original, que o envio em
// `FormData` leva (`spa/dialogos`).
function montarArquivos(alvo) {
  alvo.find('input[type="file"]:not(.textbox-value)').each(function () {
    // O `filebox` nasce de um campo comum e cria o `input type=file` dele, com o mesmo nome.
    const original = $(this)
    const id = original.attr("id")
    const campo = $('<input type="text">').attr("name", original.attr("name"))
    original.replaceWith(campo)
    campo.filebox({
      buttonText: "Escolher arquivo", buttonAlign: "right", width: "100%", height: 30, prompt: "Nenhum arquivo escolhido", accept: original.attr("accept") || "",
      onChange() { campo.closest("form").trigger("spa:mudou") },
    })
    if (id) campo.filebox("textbox").attr("id", id)
  })
}

function montarAbasInternas(alvo) {
  alvo.find("[data-abas]:not(.tabs-container)").each(function () {
    $(this).trigger("spa:abas-internas")
  })
}

export function montar(alvo) {
  alvo.find("[data-largura]").each(function () { this.style.width = `${this.dataset.largura}px` })
  alvo.find("[data-spa-layout]:not(.layout)").layout({ fit: true })
  montarEscolhas(alvo)
  montarDatas(alvo)
  montarArquivos(alvo)
  montarDeslizantes(alvo)
  alvo.find("table[data-grade]:not(.datagrid-f)").each(function () { montarGrade(this) })
  alvo.find(".tabela > table").each(function () { transformarTabela(this) })
  montarAbasInternas(alvo)
  montarCalculos(alvo)
  alvo.find("form").each(function () { aplicarCondicionais($(this)) })
  aplicarLimites(alvo)
  alvo.trigger("spa:montado")
}

// Ao mostrar uma aba escondida, grade e leiaute recalculam a largura.
export function redimensionar(alvo) {
  alvo.find(".layout").each(function () { if ($(this).data("layout")) $(this).layout("resize") })
  alvo.find(".tabs-container").each(function () { if ($(this).data("tabs")) $(this).tabs("resize") })
  alvo.find(".datagrid-f").each(function () { $(this).datagrid("resize") })
}
