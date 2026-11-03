// Divergência de um título (05, R99, R100): o JSON da mesma rota; tratar pelo modal compartilhado com a lista.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "crm/servico/http", "crm/servico/tratar-divergencia"],
  (Controller, JSONModel, formatMessage, http, tratarDivergencia) => {
  "use strict"

  return Controller.extend("crm.controller.Divergencia", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ o_que_mudou: [], tratamento: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      const dados = await http.obter(`/divergencias-de-valor/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(formatMessage(this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("divergencia.titulo"), [dados.titulo]))
    },

    tratar() {
      tratarDivergencia(this, this.id).then(() => this.carregar())
    },

    abrirFicha() {
      this.getOwnerComponent().getRouter().navTo("cliente", { id: String(this.getView().getModel("dados").getProperty("/cliente_id")) })
    },

    abrirTitulo() {
      this.getOwnerComponent().getRouter().navTo("titulo", { id: this.getView().getModel("dados").getProperty("/titulo_endereco").split("/").pop() })
    }
  })
})
