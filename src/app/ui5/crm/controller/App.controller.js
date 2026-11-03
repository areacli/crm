// Raiz da SPA (a entrada e a senha chamam `mostrarTela` do componente depois de mudar o modelo `sessao`): mostra a entrada sem sessão, a definição de senha com senha temporária e, senão, a casca (decisão 0025, P27).
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/core/mvc/XMLView", "sap/base/strings/formatMessage"], (Controller, XMLView, formatMessage) => {
  "use strict"

  return Controller.extend("crm.controller.App", {
    formatarTexto: formatMessage,

    onInit() {
      this.getView().addStyleClass(this.getOwnerComponent().densidade())
      this.getOwnerComponent().mostrarTela = () => this.mostrar()
      this.mostrar()
    },

    // A tela de cada estado é criada uma vez e reaproveitada.
    async mostrar() {
      const usuario = this.getOwnerComponent().getModel("sessao").getProperty("/usuario")
      const nome = !usuario ? "Entrada" : usuario.senha_temporaria ? "Senha" : "Casca"
      const raiz = this.byId("raiz")
      this.telas ??= {}
      this.telas[nome] ??= await this.getOwnerComponent().runAsOwner(() => XMLView.create({ id: this.createId(nome.toLowerCase()), viewName: `crm.view.${nome}` }))
      if (raiz.indexOfPage(this.telas[nome]) < 0) raiz.addPage(this.telas[nome])
      raiz.to(this.telas[nome].getId(), "show")
    }
  })
})
