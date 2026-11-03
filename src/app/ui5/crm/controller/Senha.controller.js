// Definição da senha no primeiro acesso (R38; decisão 0025). Os erros de cada campo vêm do servidor (R26) e ficam no próprio campo.
sap.ui.define(["sap/ui/core/mvc/Controller", "crm/servico/http", "crm/servico/sessao"], (Controller, http, sessao) => {
  "use strict"

  const CAMPOS = { password: "nova", password_confirmation: "repetir" }

  return Controller.extend("crm.controller.Senha", {
    async salvar() {
      const botao = this.byId("salvar")
      Object.values(CAMPOS).forEach((id) => this.byId(id).setValueState("None"))
      botao.setBusy(true)
      try {
        await http.alterar("/senha", { password: { password: this.byId("nova").getValue(), password_confirmation: this.byId("repetir").getValue() } })
        this.getOwnerComponent().getModel("sessao").setProperty("/usuario/senha_temporaria", false)
        this.getOwnerComponent().mostrarTela()
      } catch (erro) {
        Object.entries(erro.corpo?.erros || {}).forEach(([campo, mensagens]) => this.byId(CAMPOS[campo])?.setValueState("Error").setValueStateText(mensagens.join(" ")))
        this.byId("mensagem").setText(erro.corpo?.mensagem || erro.message).setVisible(true)
      } finally {
        botao.setBusy(false)
      }
    },

    sair() {
      sessao.sair(this.getOwnerComponent())
    }
  })
})
