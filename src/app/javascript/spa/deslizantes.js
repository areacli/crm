// Valor (em reais ou percentual, os dois em centésimos na faixa) com controle deslizante (design system, revisão 22) e os limites que o cálculo à vista devolve a cada mudança (`data-spa-limites`): a faixa dos
// deslizantes, as opções das listas e os textos de ajuda. O campo de texto é o que vai ao servidor; o controle só o preenche.
const $ = window.jQuery

const centavosDe = (texto) => {
  const numero = Number(String(texto ?? "").trim().replace(/\./g, "").replace(",", "."))
  return Number.isFinite(numero) ? Math.round(numero * 100) : null
}
const emReais = (centavos) => (centavos / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const emPercentual = (centesimos) => (centesimos / 100).toLocaleString("pt-BR", { maximumFractionDigits: 2, useGrouping: false })
const escrever = (bloco, centesimos) => (bloco.data("unidade") === "percentual" ? emPercentual(centesimos) : emReais(centesimos))

const controleDe = (bloco) => bloco.find(".trilho-do-deslizante > input").first()

// Muda o controle sem contar como mudança da pessoa.
// Faixa de um valor só (o desconto com teto zero): o controle fica travado. O EasyUI divide pela largura da faixa, que não pode ser zero.
function definirFaixa(bloco, minimo, maximo) {
  const controle = controleDe(bloco)
  const opcoes = controle.slider("options")
  opcoes.min = minimo
  opcoes.max = maximo > minimo ? maximo : minimo + 1
  controle.slider(maximo > minimo ? "enable" : "disable")
}

function posicionar(bloco, centavos) {
  bloco.data("sincronizando", true)
  controleDe(bloco).slider("setValue", centavos)
  bloco.data("sincronizando", false)
}

export function montarDeslizantes(alvo) {
  alvo.find("[data-spa-deslizante]:not([data-montado])").each(function () {
    const bloco = $(this).attr("data-montado", "1")
    const campo = bloco.find("input[type=text]").first()
    const minimo = Number(bloco.data("minimo"))
    const maximo = Number(bloco.data("maximo"))
    const trilho = bloco.find(".trilho-do-deslizante")
    $("<input>").appendTo(trilho).slider({
      width: trilho.width() || 240, min: minimo, max: maximo > minimo ? maximo : minimo + 1, disabled: maximo <= minimo, step: 1, value: centavosDe(campo.val()) ?? minimo, showTip: false,
      onChange(valor) {
        if (bloco.data("sincronizando")) return
        // Arrastando, os valores saem em reais inteiros, menos nas pontas da faixa, que são as da regra.
        const opcoes = $(this).slider("options")
        const exato = valor === opcoes.min || valor === opcoes.max ? valor : Math.round(valor / 100) * 100
        bloco.find("[data-deslizante-auto]").val("0")
        campo.val(escrever(bloco, exato)).trigger("input", [{ doControle: true }])
      },
    })
    // O controle tem largura em pixels: acompanha o trilho quando a coluna muda (menu recolhido, janela, bloco que estava escondido).
    let largura = trilho.width()
    new ResizeObserver(() => {
      const agora = trilho.width()
      if (agora > 0 && agora !== largura) { largura = agora; controleDe(bloco).slider("resize", { width: agora }) }
    }).observe(trilho[0])
    campo.on("input", (_evento, origem) => {
      if (origem?.doControle) return
      bloco.find("[data-deslizante-auto]").val("0")
      const centavos = centavosDe(campo.val())
      if (centavos !== null) posicionar(bloco, centavos)
    })
  })
}

function aplicarDeslizante(form, nome, { minimo, maximo, inicial }) {
  const campo = form.find(`input[type=text][name="${nome}"]`)
  const bloco = campo.closest("[data-spa-deslizante]")
  if (!bloco.length) return
  const teto = Math.max(maximo, minimo)
  definirFaixa(bloco, minimo, teto)
  bloco.closest("[data-some-sem-maximo]").toggle(teto > 0)
  const automatico = bloco.find("[data-deslizante-auto]").val() === "1"
  const atual = centavosDe(campo.val()) ?? minimo
  if (automatico && inicial !== undefined) {
    campo.val(escrever(bloco, inicial))
    posicionar(bloco, inicial)
    return
  }
  // Quem está digitando vê a recusa da regra; fora disso, o valor que saiu da faixa volta para ela e a conta se refaz.
  if ((atual < minimo || atual > teto) && !campo.is(":focus")) {
    const dentro = Math.min(Math.max(atual, minimo), teto)
    campo.val(escrever(bloco, dentro))
    posicionar(bloco, dentro)
    campo.trigger("input", [{ doControle: true }])
    return
  }
  posicionar(bloco, atual)
}

function aplicarEscolha(form, nome, lista) {
  const escolha = form.find(`input.textbox-value[name="${nome}"]`).closest(".textbox").prev(".combobox-f")
  if (!escolha.length || escolha.data("opcoes-atuais") === JSON.stringify(lista)) return
  escolha.data("opcoes-atuais", JSON.stringify(lista))
  const atual = escolha.combobox("getValue")
  const dados = lista.map(([value, text]) => ({ value: String(value), text }))
  escolha.combobox("loadData", dados)
  // A opção escolhida que deixou de existir vira a última da lista, e a mudança refaz a conta.
  escolha.combobox("setValue", dados.some((opcao) => opcao.value === atual) ? atual : dados[dados.length - 1].value)
}

export function aplicarLimites(alvo) {
  alvo.find("[data-spa-limites]").each(function () {
    const limites = $(this).data("spa-limites")
    const form = $(this).closest(".aba-conteudo, .janela-corpo, .dialogo-conteudo, body").find("form[data-calculo]").first()
    Object.entries(limites.deslizantes || {}).forEach(([nome, faixa]) => aplicarDeslizante(form, nome, faixa))
    Object.entries(limites.escolhas || {}).forEach(([nome, lista]) => aplicarEscolha(form, nome, lista))
    Object.entries(limites.textos || {}).forEach(([id, texto]) => form.find(`[id="${id}"]`).text(texto))
  })
}
