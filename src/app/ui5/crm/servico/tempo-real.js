// Tempo real com dados (decisão 0025): a conexão do Action Cable no fluxo do usuário. Cada mensagem traz o recurso e os registros já no
// formato da tela; as views abertas que acompanham o recurso aplicam no próprio modelo. Na (re)conexão, as views recarregam o que mostram.
// Sem polling.
sap.ui.define([], () => {
  "use strict"

  const ouvintes = new Map() // recurso → Set de funções
  let consumidor

  function avisar(recurso, mensagem) {
    ouvintes.get(recurso)?.forEach((ouvinte) => ouvinte(mensagem))
  }

  return {
    async iniciar() {
      if (consumidor) return
      const { createConsumer } = await import(document.querySelector("meta[name=actioncable-module]").content)
      consumidor = createConsumer()
      consumidor.subscriptions.create({ channel: "LiveChannel" }, {
        connected: () => avisar("*conectado", {}),
        received: (mensagem) => avisar(mensagem.recurso, mensagem)
      })
    },

    // `recurso` "*conectado" é chamado a cada (re)conexão. Devolve a função que desliga o ouvinte (ao fechar a aba).
    ouvir(recurso, ouvinte) {
      if (!ouvintes.has(recurso)) ouvintes.set(recurso, new Set())
      ouvintes.get(recurso).add(ouvinte)
      return () => ouvintes.get(recurso).delete(ouvinte)
    },

    // Aplica uma mensagem numa lista do modelo (por id): atualiza o que já está, inclui no topo o que é novo e retira os removidos.
    aplicar(modelo, caminho, mensagem) {
      const linhas = [...(modelo.getProperty(caminho) || [])]
      ;(mensagem.registros || []).forEach((registro) => {
        const indice = linhas.findIndex((linha) => linha.id === registro.id)
        indice >= 0 ? (linhas[indice] = registro) : linhas.unshift(registro)
      })
      const removidos = new Set(mensagem.removidos || [])
      modelo.setProperty(caminho, linhas.filter((linha) => !removidos.has(linha.id)))
    }
  }
})
