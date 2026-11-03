// Conferência do impacto do enquadramento das filas (15, R357): o JSON da mesma rota; enquanto confere, espera o fim pelo recurso `credores` do
// tempo real. Confirmar aplica e volta ao enquadramento; descartar só fecha a aba.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/tempo-real"],
  (Controller, JSONModel, MessageToast, MessageBox, http, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.ConferenciaDasFilas", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.filtro = argumentos["?filtro"] || {}
      this.aba = aba
      this.getView().setModel(new JSONModel({ conferindo: true, como_fica: [], linhas: [] }), "dados")
      this.desligar = [
        tempoReal.ouvir("credores", () => { if (this.getView().getModel("dados").getProperty("/conferindo")) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    consulta() {
      return `tenant_id=${encodeURIComponent(this.filtro.tenant_id || "")}&token=${encodeURIComponent(this.filtro.token || "")}`
    },

    async carregar() {
      try {
        this.getView().getModel("dados").setData(await http.obter(`/filas/enquadramento/conferencia.json?${this.consulta()}`))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    voltar() {
      this.getOwnerComponent().getRouter().navTo("enquadramentoDasFilas", { "?filtro": { tenant_id: this.filtro.tenant_id } })
    },

    async confirmar() {
      try {
        const resposta = await http.enviar(`/filas/enquadramento/confirmar?${this.consulta()}`, {})
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.voltar()
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    descartar() {
      this.voltar()
    }
  })
})
