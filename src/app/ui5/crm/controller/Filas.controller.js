// Visão das filas (15, R357): o JSON da mesma rota, por credor. Tempo real: refaz quando as filas do credor mudam (recurso `credores`).
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "crm/servico/http", "crm/servico/tempo-real", "crm/servico/liberar-entrega"],
  (Controller, JSONModel, http, tempoReal, liberarEntrega) => {
  "use strict"

  return Controller.extend("crm.controller.Filas", {
    onInit() {
      this.credor = this.getView().getViewData()?.argumentos?.["?filtro"]?.tenant_id || ""
      this.getView().setModel(new JSONModel({ credores: [], filas: [], entregas: [] }), "dados")
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => { if (mensagem.acao !== "atualizar" || mensagem.registros.some((credor) => String(credor.id) === this.credor)) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    async carregar() {
      const dados = await http.obter(`/filas.json?tenant_id=${encodeURIComponent(this.credor)}`)
      this.credor = dados.credor_id
      this.getView().getModel("dados").setData(dados)
    },

    mudarCredor(evento) {
      this.credor = evento.getParameter("item").getKey()
      this.carregar()
    },

    abrirFila(evento) {
      this.getOwnerComponent().getRouter().navTo("fila", { id: String(evento.getSource().getBindingContext("dados").getProperty("id")), "?filtro": { tenant_id: this.credor } })
    },

    liberar(evento) {
      liberarEntrega(evento.getSource().getBindingContext("dados").getProperty("id")).then(() => this.carregar())
    }
  })
})
