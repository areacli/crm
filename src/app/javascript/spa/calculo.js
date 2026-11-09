// Cálculo à vista (design system, 7.2): o formulário com `data-calculo` refaz o resultado no servidor enquanto a pessoa preenche. O período começa na primeira
// tecla; só a resposta da última mudança conta; a ação que usa o resultado (`data-depende-do-calculo`) só se habilita em "Calculado".
import { acompanhar } from "spa/espera"
import { montar } from "spa/montagem"

const $ = window.jQuery
const PAUSA = 500

const hora = () => new Date().toLocaleTimeString("pt-BR")

function estadoDe(form) {
  const alvo = form.closest(".aba-conteudo, .janela-corpo, .dialogo-conteudo, .lista, body").find("[data-resultado-do-calculo]").first()
  let estado = alvo.prev(".estado-do-calculo")
  if (!estado.length) estado = $('<p class="estado-do-calculo" role="status" aria-live="polite"></p>').insertBefore(alvo)
  return { alvo, estado }
}

function mostrar(form, situacao, texto) {
  const { alvo, estado } = estadoDe(form)
  estado.attr("data-situacao", situacao).empty()
  if (situacao === "calculando") estado.append('<span class="girando" aria-hidden="true"></span> ')
  estado.append(document.createTextNode(texto))
  alvo.toggleClass("desatualizado", situacao === "calculando").attr("aria-busy", String(situacao === "calculando"))
  form.find("[data-depende-do-calculo]").prop("disabled", situacao !== "calculado")
  return { alvo, estado }
}

// O servidor diz no próprio resultado se falta dado ou se a regra recusou; sem marca, a conta foi feita.
function situacaoDoResultado(alvo) {
  if (alvo.find('[data-calculo="incompleto"]').length) return ["incompleto", ""]
  if (alvo.find('[data-calculo="recusado"]').length) return ["recusado", ""]
  return ["calculado", `Calculado às ${hora()}`]
}

// O cálculo é sempre um POST para o endereço dele: o `_method` do formulário de edição (PATCH) não vai junto.
export const semMetodo = (form) => $.param(form.serializeArray().filter((campo) => campo.name !== "_method"))

function calcular(form) {
  const numero = (form.data("calculo-numero") || 0) + 1
  form.data("calculo-numero", numero)
  form.data("calculo-pedido")?.abort()
  const pedido = $.ajax({ url: form.data("calculo"), method: "POST", data: semMetodo(form), dataType: "html", headers: { "X-CRM-Calculo": "1" } })
  form.data("calculo-pedido", pedido)
  const { alvo } = estadoDe(form)
  acompanhar(alvo, pedido)
  pedido
    .done((html) => {
      if (form.data("calculo-numero") !== numero) return
      alvo.html(html)
      montar(alvo)
      mostrar(form, ...situacaoDoResultado(alvo))
    })
    .fail((xhr, situacao) => {
      if (situacao === "abort" || form.data("calculo-numero") !== numero) return
      const { estado } = mostrar(form, "falhou", "Não foi possível calcular. ")
      alvo.empty()
      $('<button type="button" data-variant="secondary" data-size="small">Tentar de novo</button>').on("click", () => mudou(form, true)).appendTo(estado)
    })
}

function mudou(form, agora = false) {
  form.data("calculo-pedido")?.abort()
  clearTimeout(form.data("calculo-relogio"))
  clearTimeout(form.data("calculo-ainda"))
  mostrar(form, "calculando", "Calculando…")
  form.data("calculo-ainda", setTimeout(() => { if (estadoDe(form).estado.attr("data-situacao") === "calculando") mostrar(form, "calculando", "Ainda calculando…") }, 3000))
  form.data("calculo-relogio", setTimeout(() => calcular(form), agora ? 0 : PAUSA))
}

// O resultado que veio com a página já é o da tela: o estado parte dele.
export function montarCalculos(alvo) {
  alvo.find("form[data-calculo]").each(function () {
    const form = $(this)
    const { alvo: resultado } = estadoDe(form)
    mostrar(form, ...situacaoDoResultado(resultado).map((v, i) => (i === 1 && v ? "Calculado com os dados da tela" : v)))
  })
}

$(document).on("input change spa:mudou", "form[data-calculo]", function (evento) {
  if ($(evento.target).is("[data-depende-do-calculo]")) return
  // O texto já avisou a cada tecla (`input`); o `change` dele vem ao sair do campo, que é o clique em "Salvar" logo depois de digitar: recalcular ali
  // desabilitaria o botão no meio do clique, e o clique se perderia.
  if (evento.type === "change" && $(evento.target).is("textarea, input:not([type=checkbox], [type=radio], [type=file], [type=hidden])")) return
  mudou($(this))
})
