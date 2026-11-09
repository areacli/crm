// Edição inline (design system, 7.1): sob pedido, pelo "Editar" junto ao valor. Enter ou Salvar grava, Esc ou Descartar volta ao valor; sair do campo não grava
// e a edição fica aberta como rascunho da aba; o erro aparece junto ao campo, que continua com o que foi digitado.
import { acompanhar } from "spa/espera"
import { esc } from "spa/formatos"

const $ = window.jQuery

function abrir(caixa) {
  const dados = caixa.data("inline")
  const valor = caixa.find(".inline-valor").text()
  const form = $('<form class="inline-editando" novalidate> <button type="submit" data-size="small">Salvar</button> <button type="button" data-variant="secondary" data-size="small" data-inline-descartar>Descartar</button><span class="inline-erro" role="alert"></span></form>')
  // Com `opcoes`, uma lista de escolha nativa (o valor mostrado é o texto da opção; o enviado, o valor dela); sem, o campo de texto.
  const campo = dados.opcoes
    ? $("<select>").append(dados.opcoes.map(([texto, opcao]) => $("<option>").val(opcao).text(texto))).val(dados.selecionado)
    : $('<input type="text">').attr("maxlength", dados.maximo || 200).val(valor)
  campo.attr({ name: dados.nome, "aria-label": dados.rotulo })
  form.prepend(campo)
  form.data({ caixa, original: valor })
  caixa.hide().after(form)
  caixa.trigger("inline:celula", [true])
  campo.trigger("focus")
  if (!dados.opcoes) campo.trigger("select")
}

function fechar(form, valor) {
  const caixa = form.data("caixa")
  if (valor !== undefined) caixa.find(".inline-valor").text(valor)
  caixa.show()
  form.remove()
  caixa.trigger("inline:celula", [false])
  caixa.find("[data-inline-editar]").trigger("focus")
  caixa.closest(".aba-raiz").trigger("inline:fechou")
}

function salvar(form) {
  if (form.data("enviando")) return
  const caixa = form.data("caixa")
  const dados = caixa.data("inline")
  const campo = form.find("input, select")
  const digitado = campo.is("select") ? campo.find("option:selected").text() : campo.val()
  form.data("enviando", true).find("button").prop("disabled", true)
  form.find("button[type=submit]").addClass("carregando")
  const pedido = $.ajax({ url: dados.url, method: "POST", data: `${form.serialize()}&_method=${dados.metodo || "patch"}`, dataType: "text", headers: { "X-CRM-Inline": "1" } })
  acompanhar(form, pedido)
  pedido
    .done((_texto, _situacao, xhr) => {
      const evento = JSON.parse(xhr.getResponseHeader("X-CRM-Evento") || "{}")
      const raiz = caixa.closest(".aba-raiz")
      fechar(form, evento.valor ?? digitado)
      if (evento.aviso) $.messager.show({ title: "Feito", msg: esc(evento.aviso), timeout: 3200, showType: "slide" })
      if (evento.atualizar) raiz.trigger("spa:recarregar")
    })
    .fail((xhr) => {
      form.removeData("enviando").find("button").prop("disabled", false).removeClass("carregando")
      let texto = xhr.status === 0 ? "Sem resposta do servidor. Confira se foi gravado antes de repetir." : "Não foi possível salvar."
      try { texto = JSON.parse(xhr.responseText).erro || texto } catch { /* resposta sem JSON */ }
      form.find(".inline-erro").text(texto)
      campo.attr("aria-invalid", "true").trigger("focus")
      caixa.trigger("inline:celula", [true])
    })
}

$(document).on("click", "[data-inline-editar]", function () { abrir($(this).closest("[data-inline]")) })
// "Editar" no menu da linha: abre o campo da mesma linha da grade.
$(document).on("click", "[data-inline-abrir]", function () {
  this.closest("[popover]")?.hidePopover?.()
  const caixa = $(this).closest("tr").find("[data-inline]").first()
  if (caixa.is(":visible")) abrir(caixa)
})
$(document).on("input change", "form.inline-editando input, form.inline-editando select", function () { $(this).closest(".aba-raiz").trigger("inline:mudou") })
$(document).on("submit", "form.inline-editando", function (evento) { evento.preventDefault(); evento.stopPropagation(); salvar($(this)) })
$(document).on("click", "[data-inline-descartar]", function () { const form = $(this).closest("form"); fechar(form, form.data("original")) })
$(document).on("keydown", "form.inline-editando input, form.inline-editando select", function (evento) {
  if (evento.key === "Escape") { evento.preventDefault(); const form = $(this).closest("form"); fechar(form, form.data("original")) }
})
