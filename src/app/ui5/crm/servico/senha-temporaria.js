// Senha temporária (R37): aparece uma única vez, só para quem fez a ação, quando a resposta da ação a traz (criar usuário, credenciar operação).
sap.ui.define(["sap/m/MessageBox"], (MessageBox) => {
  "use strict"

  return (controlador, resposta) => {
    const senha = resposta?.senha_temporaria
    if (!senha) return
    const i18n = controlador.getOwnerComponent().getModel("i18n").getResourceBundle()
    MessageBox.success(i18n.getText("senhaTemporaria.texto", [senha.email, senha.password]), { title: i18n.getText("senhaTemporaria.titulo") })
  }
})
