// Página da importação (R10, R56): o JSON da mesma rota do servidor. Tempo real: a situação e o andamento chegam pelo recurso `importacoes`;
// quando a situação muda (conferida, gravada, recusada), a página se refaz para trazer o resultado.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "crm/servico/http", "crm/servico/tempo-real", "crm/servico/confirmar-importacao"],
  (Controller, JSONModel, formatMessage, http, tempoReal, confirmarImportacao) => {
  "use strict"

  return Controller.extend("crm.controller.Importacao", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = Number(argumentos.id)
      this.aba = aba
      this.getView().setModel(new JSONModel({ situacao: {} }), "dados")
      this.desligar = [tempoReal.ouvir("importacoes", (mensagem) => this.atualizar(mensagem)), tempoReal.ouvir("*conectado", () => this.carregar())]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    async carregar() {
      const dados = await http.obter(`/importacoes/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(formatMessage(this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("importacao.titulo"), [dados.recebida]))
    },

    // O andamento troca só a barra; a mudança de situação refaz a página.
    atualizar(mensagem) {
      if (mensagem.acao !== "atualizar") return this.carregar()
      const registro = mensagem.registros.find((item) => item.id === this.id)
      if (!registro) return
      const dados = this.getView().getModel("dados")
      if (registro.situacao.texto !== dados.getProperty("/situacao/texto")) return this.carregar()
      dados.setProperty("/percentual", registro.percentual)
      dados.setProperty("/trabalhando", registro.trabalhando)
    },

    confirmar() {
      confirmarImportacao(this, this.getView().getModel("dados").getData(), "confirmar").then(() => this.carregar())
    },

    descartar() {
      confirmarImportacao(this, this.getView().getModel("dados").getData(), "descartar").then(() => this.carregar())
    }
  })
})
