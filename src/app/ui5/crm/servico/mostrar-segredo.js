// Segredo do webhook (método de recebimento e integração): aparece uma única vez, quando a resposta da ação o traz.
sap.ui.define(["sap/m/MessageBox"], (MessageBox) => {
  "use strict"

  return (controlador, resposta) => {
    if (!resposta?.segredo) return
    const i18n = controlador.getOwnerComponent().getModel("i18n").getResourceBundle()
    MessageBox.warning(i18n.getText("segredo.texto", [resposta.segredo]), { title: i18n.getText("segredo.titulo") })
  }
})
