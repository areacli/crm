// Página do segmento (13, R278): o JSON da mesma rota. Tempo real pelo recurso `credores`: a situação e o uso mudam quando o credor do segmento muda.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageBox", "crm/servico/http", "crm/servico/tempo-real"],
  (Controller, JSONModel, MessageBox, http, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Segmento", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({}), "dados")
      const credor = () => String(this.getView().getModel("dados").getProperty("/credor_id"))
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => { if (mensagem.acao !== "atualizar" || (mensagem.registros || []).some((item) => String(item.id) === credor())) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    async carregar() {
      try {
        const dados = await http.obter(`/configuracao/segmentos/${this.id}.json`)
        this.getView().getModel("dados").setData(dados)
        this.aba?.setName(dados.nome)
      } catch (erro) {
        const i18n = this.getOwnerComponent().getModel("i18n").getResourceBundle()
        MessageBox.error(erro.status === 404 ? i18n.getText("segmentos.naoEncontrado") : erro.corpo?.mensagem || erro.message)
      }
    },

    editar() {
      this.getOwnerComponent().getRouter().navTo("editarSegmento", { id: this.id })
    }
  })
})
