// Glossário dos segmentos (13, R289): o JSON da mesma rota, sem tempo real (o catálogo só muda com o sistema). As seções no alto levam ao cartão.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageBox", "crm/servico/http"], (Controller, JSONModel, MessageBox, http) => {
  "use strict"

  return Controller.extend("crm.controller.GlossarioDosSegmentos", {
    onInit() {
      this.getView().setModel(new JSONModel({ secoes: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      try {
        this.getView().getModel("dados").setData(await http.obter("/configuracao/segmentos/glossario.json"))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    // Leva ao cartão da seção e põe o foco no título dele, para o leitor de tela seguir junto.
    irParaSecao(evento) {
      const indice = Number(evento.getSource().getBindingContext("dados").getPath().split("/").pop())
      const cartao = this.byId("secoes").getItems()[indice]
      const elemento = cartao?.getDomRef()
      if (!elemento) return
      elemento.scrollIntoView({ block: "start", behavior: "smooth" })
      elemento.querySelector("[tabindex]")?.focus({ preventScroll: true })
    },

    voltar() {
      this.getOwnerComponent().getRouter().navTo("segmentos", {})
    }
  })
})
