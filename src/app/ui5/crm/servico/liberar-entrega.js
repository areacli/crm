// Liberar a entrega de um operador (15, R354, R357): botão direto, compartilhado pela visão das filas e pela página de uma fila.
sap.ui.define(["sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http"], (MessageToast, MessageBox, http) => {
  "use strict"

  return async (id) => {
    try {
      const resposta = await http.enviar(`/filas/entregas/${id}/liberar`, {})
      MessageToast.show(resposta.mensagem, { duration: 6000 })
    } catch (erro) {
      MessageBox.error(erro.corpo?.mensagem || erro.message)
    }
  }
})
