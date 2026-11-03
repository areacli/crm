// Para onde vai a tela depois de uma ação dos segmentos (13, R272): o servidor responde o destino do redirect. A lista dos segmentos fica onde
// está (a tela se refaz); o que a SPA tem (a conferência do impacto do enquadramento financeiro, por exemplo) abre numa aba; o resto, como página
// do servidor.
sap.ui.define(["crm/servico/telas"], (telas) => {
  "use strict"

  const LISTA = "/configuracao/segmentos"

  return {
    // Devolve true quando a tela saiu para outro lugar (aba ou página do servidor).
    seguir(controlador, resposta) {
      if (!resposta?.destino) return false
      const endereco = new URL(resposta.destino, window.location.origin)
      if (endereco.pathname === LISTA) return false
      const destino = telas.doCaminho(endereco.pathname + endereco.search) || telas.doCaminho(endereco.pathname)
      if (destino) {
        controlador.getOwnerComponent().getRouter().navTo(destino.tela.rota, destino.argumentos)
      } else {
        window.location.assign(resposta.destino)
      }
      return true
    }
  }
})
