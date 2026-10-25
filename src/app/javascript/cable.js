// WebSocket do Action Cable. O servidor só transmite eventos de invalidação pequenos ({ event, ... }); aqui eles viram eventos
// do DOM (`cable:<event>`), e o trecho que depende deles se refaz sozinho: hx-trigger="cable:import-changed from:body".
// Os canais vêm da página: <meta name="cable-channels" content='[{"channel":"TenantChannel","tenant_id":1}]'>.
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()
const canais = JSON.parse(document.querySelector("meta[name=cable-channels]")?.content ?? "[]")

const avisar = (nome, detalhe = {}) => document.body.dispatchEvent(new CustomEvent(`cable:${nome}`, { detail: detalhe }))

canais.forEach((parametros) => {
  consumer.subscriptions.create(parametros, {
    // Difusão perdida durante uma queda não se repete: a cada (re)conexão as telas se ressincronizam.
    connected() { avisar("connected", parametros) },
    received(dados) { avisar(dados.event, dados) },
  })
})

window.cable = { consumer, canais }
