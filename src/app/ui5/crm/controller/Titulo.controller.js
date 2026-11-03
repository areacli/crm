// Página do título (R100; 09, R174): o JSON da mesma rota do servidor. Tempo real: refaz quando o cliente do título muda (recurso `clientes`).
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Popover", "sap/m/Text", "crm/servico/http", "crm/servico/tempo-real"],
  (Controller, JSONModel, formatMessage, Popover, Text, http, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Titulo", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ indicadores: [], notas: [], composicao: [], versoes: [], eventos: [], memoria: null }), "dados")
      this.desligar = [
        tempoReal.ouvir("clientes", (mensagem) => { if ((mensagem.registros || []).some((cliente) => cliente.id === this.clienteId())) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    clienteId() {
      return this.getView().getModel("dados").getProperty("/cliente_id")
    },

    async carregar() {
      const dados = await http.obter(`/titulos/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(formatMessage(this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("titulo.titulo"), [dados.numero]))
    },

    mostrarDefinicao(evento) {
      const botao = evento.getSource()
      const popover = new Popover({ title: botao.getTooltip(), contentWidth: "20rem", content: [new Text({ text: botao.data("definicao") }).addStyleClass("sapUiSmallMargin")], afterClose: () => popover.destroy() })
      popover.openBy(botao)
    },

    abrirFicha() {
      this.getOwnerComponent().getRouter().navTo("cliente", { id: String(this.clienteId()) })
    },

    abrirAcordo(evento) {
      this.getOwnerComponent().getRouter().navTo("acordo", { id: String(evento.getSource().getBindingContext("dados").getProperty("acordo_id")) })
    }
  })
})
