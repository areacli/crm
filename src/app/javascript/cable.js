// WebSocket do Action Cable. O servidor só transmite eventos de invalidação pequenos ({ event, ... }); aqui eles viram eventos
// do DOM (`cable:<event>`), e o trecho que depende deles se refaz sozinho: hx-trigger="cable:import-changed from:body".
// Os canais vêm da página: <meta name="cable-channels" content='[{"channel":"TenantChannel","tenant_id":1}]'>. Como o corpo é trocado pelo
// htmx (`hx-boost`) sem recarregar o <head>, a lista de canais da página nova é lida da resposta e as assinaturas são acertadas: sai o que a página
// nova não usa, entra o que ela pede (sem isso, depois do login ou de um link, o sino e as telas ao vivo ficariam sem assinatura).
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()
const assinaturas = new Map()

// O htmx descarta o evento que chega enquanto a busca do mesmo trecho está em andamento. Um aviso assim se perderia (a importação fica "conferida" milissegundos
// depois do aviso de andamento, e a tela ficava no andamento): guarda-se o instante de cada aviso e, quando a busca de um trecho ao vivo termina, o aviso que chegou
// durante ela é disparado de novo (uma vez; o reenvio não conta como aviso novo, então não gera laço).
const instantes = {}
const buscando = new Map()

const avisar = (nome, detalhe = {}) => {
  instantes[nome] = performance.now()
  document.body.dispatchEvent(new CustomEvent(`cable:${nome}`, { detail: detalhe }))
}

const aoVivo = (elemento) => elemento?.getAttribute?.("hx-trigger")?.includes("cable:")

document.addEventListener("htmx:beforeRequest", (evento) => {
  if (aoVivo(evento.target) && evento.target.id) buscando.set(evento.target.id, performance.now())
})
document.addEventListener("htmx:afterSettle", (evento) => {
  const inicio = buscando.get(evento.target?.id)
  if (inicio === undefined) return

  buscando.delete(evento.target.id)
  Object.keys(instantes).filter((nome) => instantes[nome] > inicio).forEach((nome) => document.body.dispatchEvent(new CustomEvent(`cable:${nome}`)))
})

const canaisDa = (conteudo) => {
  try { return JSON.parse(conteudo || "[]") } catch { return [] }
}

function sincronizar() {
  const pedidos = new Map(canaisDa(document.querySelector("meta[name=cable-channels]")?.content).map((parametros) => [JSON.stringify(parametros), parametros]))
  for (const [chave, assinatura] of assinaturas) {
    if (!pedidos.has(chave)) {
      assinatura.unsubscribe()
      assinaturas.delete(chave)
    }
  }
  for (const [chave, parametros] of pedidos) {
    if (assinaturas.has(chave)) continue

    assinaturas.set(chave, consumer.subscriptions.create(parametros, {
      // Difusão perdida durante uma queda não se repete: a cada (re)conexão as telas se ressincronizam.
      connected() {
        document.documentElement.dataset.cable = "conectado"
        avisar("connected", parametros)
      },
      received(dados) { avisar(dados.event, dados) },
    }))
  }
}

// A resposta de uma navegação do htmx traz a lista de canais da página nova; o <head> atual guarda a da anterior.
document.addEventListener("htmx:beforeSwap", (evento) => {
  if (!(evento.detail.boosted || evento.detail.requestConfig?.boosted) || typeof evento.detail.serverResponse !== "string") return

  const novo = new DOMParser().parseFromString(evento.detail.serverResponse, "text/html").querySelector("meta[name=cable-channels]")
  const atual = document.querySelector("meta[name=cable-channels]")
  if (novo && atual) atual.content = novo.content
})
document.addEventListener("htmx:afterSettle", (evento) => {
  if (evento.detail.boosted || evento.detail.requestConfig?.boosted) sincronizar()
})

sincronizar()
window.cable = { consumer, get canais() { return [...assinaturas.values()].map((a) => JSON.parse(a.identifier)) } }
