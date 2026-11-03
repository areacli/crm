// Confirmar ou descartar uma importação conferida (R10, R56): a pergunta curta com a consequência, compartilhada pela lista e pela página.
sap.ui.define(["sap/m/MessageBox", "sap/m/MessageToast", "crm/servico/http"], (MessageBox, MessageToast, http) => {
  "use strict"

  return (controlador, importacao, acao) => new Promise((resolver) => {
    const i18n = controlador.getOwnerComponent().getModel("i18n").getResourceBundle()
    const confirmar = acao === "confirmar"
    const botao = i18n.getText(confirmar ? "importacao.confirmar" : "importacao.descartar")
    MessageBox[confirmar ? "confirm" : "warning"](confirmar ? importacao.mensagem_de_confirmar : importacao.mensagem_de_descartar, {
      title: i18n.getText(confirmar ? "importacao.confirmar.pergunta" : "importacao.descartar.pergunta"),
      actions: [botao, MessageBox.Action.CANCEL], emphasizedAction: botao,
      onClose: async (escolha) => {
        if (escolha !== botao) return resolver(false)
        try {
          const resposta = await http.enviar(`/importacoes/${importacao.id}/${confirmar ? "confirmacao" : "descarte"}`, {})
          MessageToast.show(resposta.mensagem, { duration: 6000 })
        } catch (erro) {
          MessageBox.error(erro.corpo?.mensagem || erro.message)
        }
        resolver(true)
      }
    })
  })
})
