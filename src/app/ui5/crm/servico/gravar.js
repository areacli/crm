// Gravar um formulário em linha das páginas de configuração (modelo Configuração): envia à rota de sempre e mostra o aviso ou a recusa; a tela se refaz.
sap.ui.define(["sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http"], (MessageToast, MessageBox, http) => {
  "use strict"

  return async (controlador, metodo, url, corpo) => {
    try {
      const resposta = await http[metodo](url, corpo)
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      return resposta || {}
    } catch (erro) {
      MessageBox.error(erro.corpo?.mensagem || erro.message)
      return null
    } finally {
      controlador.carregar?.()
    }
  }
})
