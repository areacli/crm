// Confirmação curta (regra de ação): pergunta com a consequência e o verbo da ação no botão; executa e mostra o aviso ou a recusa.
sap.ui.define(["sap/m/MessageBox", "sap/m/MessageToast"], (MessageBox, MessageToast) => {
  "use strict"

  return ({ titulo, mensagem, acao, perigosa = true, executar }) => new Promise((resolver) => {
    MessageBox[perigosa ? "warning" : "confirm"](mensagem, {
      title: titulo, actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
      onClose: async (escolha) => {
        if (escolha !== acao) return resolver(null)
        try {
          const resposta = await executar()
          if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
          resolver(resposta || {})
        } catch (erro) {
          MessageBox.error(erro.corpo?.mensagem || erro.message)
          resolver(null)
        }
      }
    })
  })
})
