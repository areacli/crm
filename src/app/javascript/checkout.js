// Página pública de pagamento (12, parte C). Cartão só por checkout transparente (R278): os campos do cartão não têm `name` e nunca são enviados;
// a biblioteca do fornecedor (declarada no manifesto do adaptador e fixada em vendor/javascript) transforma o cartão em `payment_token` aqui no
// navegador, e o formulário envia ao servidor só esse token e as parcelas. Sem polling: o resultado do cartão volta na resposta do POST e, para Pix e
// boleto pagos depois, a área de pagamento se refaz sozinha quando o canal do link avisa (cable:checkout-changed).
import htmx from "htmx.org"
import "cable"

window.htmx = htmx
htmx.config.allowEval = false
// A política de segurança de conteúdo não permite estilo embutido: nada de <style> injetado pelo htmx.
htmx.config.includeIndicatorStyles = false

document.addEventListener("htmx:configRequest", (evento) => {
  const token = document.querySelector("meta[name=csrf-token]")?.content
  if (token) evento.detail.headers["X-CSRF-Token"] = token
})

// Resposta 422 (pedido inválido, página vencida) também troca a área, para mostrar a mensagem.
document.addEventListener("htmx:beforeSwap", (evento) => {
  if (evento.detail.xhr.status === 422) {
    evento.detail.shouldSwap = true
    evento.detail.isError = false
  }
})

const carregados = new Map()

// Carrega o módulo do adaptador (driver) e a biblioteca do fornecedor, uma vez. Os nomes vêm da página (do manifesto) e são do importmap: nada de endereço externo.
const carregar = (formulario) => {
  const chave = `${formulario.dataset.driver}|${formulario.dataset.script}`
  if (!carregados.has(chave)) {
    carregados.set(chave, Promise.all([
      import(formulario.dataset.driver),
      formulario.dataset.script ? import(formulario.dataset.script) : Promise.resolve(null),
    ]).then(([driver, biblioteca]) => ({ driver, biblioteca })))
  }
  return carregados.get(chave)
}

const mensagens = (formulario) => JSON.parse(formulario.dataset.messages ?? "{}")
const configuracao = (formulario) => JSON.parse(formulario.dataset.config ?? "{}")

const mostrarErro = (formulario, texto) => {
  const area = formulario.querySelector("#cartao-erro")
  area.textContent = texto
  area.hidden = false
}

const ocupado = (formulario, sim) => {
  formulario.dataset.enviando = sim ? "1" : ""
  formulario.setAttribute("aria-busy", sim ? "true" : "false")
  formulario.querySelector("button[type=submit]").disabled = sim
}

const lerCartao = (formulario) => {
  const valor = (id) => formulario.querySelector(id).value.trim()
  const [mes = "", ano = ""] = valor("#cartao-validade").split("/").map((parte) => parte.replace(/\D/g, ""))
  return {
    number: valor("#cartao-numero").replace(/\D/g, ""),
    holderName: valor("#cartao-titular"),
    expirationMonth: mes.padStart(2, "0"),
    expirationYear: ano.length === 2 ? `20${ano}` : ano,
    cvv: valor("#cartao-codigo"),
  }
}

// Os dados do cartão saem dos campos assim que o token existe; o token é o único que segue.
const limparCartao = (formulario) => {
  formulario.querySelectorAll("#cartao-numero, #cartao-titular, #cartao-validade, #cartao-codigo").forEach((campo) => { campo.value = "" })
}

document.addEventListener("submit", async (evento) => {
  const formulario = evento.target
  if (!formulario.matches?.("form[data-cartao]")) return

  evento.preventDefault()
  if (formulario.dataset.enviando) return

  ocupado(formulario, true)
  formulario.querySelector("#cartao-erro").hidden = true
  try {
    const { driver, biblioteca } = await carregar(formulario)
    const token = await driver.tokenize(biblioteca, configuracao(formulario), lerCartao(formulario))
    formulario.querySelector("#payment-token").value = token
    // O htmx valida o formulário (campos obrigatórios) e lê os valores de forma síncrona dentro do trigger: só depois os dados do cartão saem dos campos.
    htmx.trigger(formulario, "tokenized")
    limparCartao(formulario)
  } catch (erro) {
    const textos = mensagens(formulario)
    mostrarErro(formulario, textos[`card_${erro?.reason ?? "form_error"}`] ?? textos.card_form_error)
    ocupado(formulario, false)
  }
})

// A área toda é trocada depois do POST (o formulário volta limpo, ou some quando aprovou): o próximo envio começa do zero.
document.addEventListener("htmx:afterSwap", () => carregados.size && document.querySelectorAll("form[data-cartao]").forEach((f) => ocupado(f, false)))

// Parcelas pela bandeira: só o nome da bandeira (nunca o número) vai ao servidor.
let esperaDaBandeira
document.addEventListener("input", (evento) => {
  const campo = evento.target
  if (campo.id !== "cartao-numero") return

  const formulario = campo.closest("form[data-cartao]")
  clearTimeout(esperaDaBandeira)
  esperaDaBandeira = setTimeout(async () => {
    const numero = campo.value.replace(/\D/g, "")
    if (numero.length < 6) return

    try {
      const { driver, biblioteca } = await carregar(formulario)
      const bandeira = await driver.brand(biblioteca, configuracao(formulario), numero)
      if (bandeira && formulario.dataset.bandeira !== bandeira) {
        const escolhida = formulario.querySelector("#cartao-parcelas")?.value
        await htmx.ajax("GET", `${formulario.dataset.installmentsUrl}?brand=${encodeURIComponent(bandeira)}`, { target: "#parcelas", swap: "outerHTML" })
        // A lista nova não desfaz a escolha de quem já escolheu as parcelas.
        const lista = formulario.querySelector("#cartao-parcelas")
        if (escolhida && lista?.querySelector(`option[value="${escolhida}"]`)) lista.value = escolhida
        formulario.dataset.bandeira = bandeira
      }
    } catch (erro) {
      // Sem bandeira, ficam as parcelas padrão; o erro de verdade aparece ao pagar.
    }
  }, 400)
})

// Copiar o código do Pix e a linha digitável do boleto.
document.addEventListener("click", async (evento) => {
  const botao = evento.target.closest("[data-copiar]")
  if (!botao) return

  const campo = document.getElementById(botao.dataset.copiar)
  campo.select()
  try {
    await navigator.clipboard.writeText(campo.value)
  } catch (erro) {
    document.execCommand("copy")
  }
})
