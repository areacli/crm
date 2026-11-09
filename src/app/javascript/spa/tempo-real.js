// Tempo real (decisão 0028, D9): os canais do Action Cable continuam transmitindo eventos de invalidação. Cada aba assina os canais que o trecho dela declara
// (`template.canais-do-trecho`), e um evento de um desses canais avisa a aba; o sino escuta pelo `document`. Conexão caída aparece na tela até voltar (design system, 7.2).
import { createConsumer } from "@rails/actioncable"

const $ = window.jQuery
let consumidor = null
const assinaturas = new Map()
let jaConectou = false
let aoReconectar = () => {}

const chaveDe = (parametros) => JSON.stringify(parametros)

function receber(chave, dados) {
  $(document).trigger(`cable:${dados.event}`, [dados])
  assinaturas.get(chave)?.interessados.forEach((avisar) => avisar(dados))
}

function assinatura(parametros) {
  consumidor ??= createConsumer()
  const chave = chaveDe(parametros)
  if (!assinaturas.has(chave)) {
    const registro = { interessados: new Map(), canal: null }
    assinaturas.set(chave, registro)
    registro.canal = consumidor.subscriptions.create(parametros, {
      connected() {
        $("#sem-conexao").prop("hidden", true)
        // Difusão perdida durante a queda não se repete: na volta, as telas abertas se refazem.
        if (jaConectou && registro.caiu) aoReconectar()
        registro.caiu = false
        jaConectou = true
        $(document).trigger("cable:connected", [parametros])
      },
      disconnected() { registro.caiu = true; $("#sem-conexao").prop("hidden", false) },
      received(dados) { receber(chave, dados) },
    })
  }
  return { chave, registro: assinaturas.get(chave) }
}

// Canais da casca (o sino), assinados uma vez.
export function assinar(canais, { reconectou } = {}) {
  if (reconectou) aoReconectar = reconectou
  canais.forEach((parametros) => { assinatura(parametros).registro.daCasca = true })
}

// Canais de uma aba: troca os que ela tinha pelos do trecho novo. `avisar` é chamado a cada evento.
export function assinarAba(dono, canais, avisar) {
  soltarAba(dono)
  canais.forEach((parametros) => {
    const { registro } = assinatura(parametros)
    registro.porTela = true
    registro.interessados.set(dono, avisar)
  })
}

export function soltarAba(dono) {
  for (const [chave, registro] of assinaturas) {
    registro.interessados.delete(dono)
    // Os canais da casca ficam; os de tela saem quando nenhuma aba os usa.
    if (registro.interessados.size === 0 && registro.porTela && !registro.daCasca) {
      registro.canal?.unsubscribe()
      assinaturas.delete(chave)
    }
  }
}

// Para os testes, que não têm WebSocket entre o servidor e o navegador: entrega um evento como se o canal o transmitisse.
export const simular = (parametros, dados) => receber(chaveDe(parametros), dados)
