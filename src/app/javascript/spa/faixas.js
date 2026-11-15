// Lista editável das faixas de atraso (padrões de interface, T6; 01, revisão 8): "Criar faixa" acrescenta uma linha e "Excluir" tira a linha, na hora, sem
// salvar; fica sempre ao menos uma linha e no máximo `data-maximo`. A prévia acompanha o que se digita, com a mesma conta de `Portfolio::AgingBrackets.preview`;
// quem valida (R18) é o salvar.
const $ = window.jQuery

const inteiro = (texto) => (/^\s*\d+\s*$/.test(texto || "") ? Number(texto) : null)

function refazer(bloco) {
  const linhas = bloco.find("tbody > tr")
  const maximo = Number(bloco.data("maximo"))
  // Os rótulos acompanham a posição da linha: "Faixa 3: de" é sempre a terceira linha da tabela.
  linhas.each(function (indice) {
    const numero = indice + 1
    const campos = $(this).find("input")
    campos.eq(0).attr("aria-label", `Faixa ${numero}: de`)
    campos.eq(1).attr("aria-label", `Faixa ${numero}: até`)
    $(this).find("[data-excluir-faixa]").attr("aria-label", `Excluir a faixa ${numero}`)
  })
  bloco.find("[data-criar-faixa]").prop("disabled", linhas.length >= maximo)
  const faixas = linhas.get()
    .map((linha) => { const campos = $(linha).find("input"); return [ inteiro(campos.eq(0).val()), inteiro(campos.eq(1).val()) ] })
    .filter(([ de ]) => de !== null)
    .sort((a, b) => a[0] - b[0])
  const previa = bloco.find("[data-previa-das-faixas]").empty()
  faixas.forEach(([ de, ate ]) => $("<li>").text(`${ate === null ? `mais de ${de - 1}` : `${de}–${ate}`} dias`).appendTo(previa))
}

$(document).on("click", "[data-faixas] [data-criar-faixa]", function () {
  const bloco = $(this).closest("[data-faixas]")
  if (bloco.find("tbody > tr").length >= Number(bloco.data("maximo"))) return
  const linha = $(bloco.find("template[data-modelo-da-faixa]").get(0).content.firstElementChild.cloneNode(true))
  bloco.find("tbody").append(linha)
  refazer(bloco)
  linha.find("input").first().trigger("focus")
})

$(document).on("click", "[data-faixas] [data-excluir-faixa]", function () {
  const bloco = $(this).closest("[data-faixas]")
  const linha = $(this).closest("tr")
  // A última linha que sobra não sai: fica em branco.
  if (bloco.find("tbody > tr").length === 1) linha.find("input").val("")
  else {
    // O foco vai para a linha seguinte (ou a anterior), para o teclado não se perder.
    const vizinha = linha.next("tr").length ? linha.next("tr") : linha.prev("tr")
    linha.remove()
    vizinha.find("input").first().trigger("focus")
  }
  refazer(bloco)
  bloco.closest("form").trigger("input")
})

$(document).on("input", "[data-faixas] input", function () { refazer($(this).closest("[data-faixas]")) })
