// Lote de distribuição (14, R316): o JSON da mesma rota; quando a conferência ou a confirmação termina, o recurso `lotes` do tempo real refaz a página.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/tempo-real"],
  (Controller, JSONModel, MessageToast, MessageBox, http, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Lote", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = Number(argumentos.id)
      this.aba = aba
      this.getView().setModel(new JSONModel({}), "dados")
      this.desligar = [
        tempoReal.ouvir("lotes", (mensagem) => { if (mensagem.acao !== "atualizar" || mensagem.registros.some((lote) => lote.id === this.id)) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    async carregar() {
      const dados = await http.obter(`/distribuicao/lotes/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(dados.titulo)
    },

    async executar(metodo, caminho) {
      try {
        const resposta = await http[metodo](`/distribuicao/lotes/${this.id}/${caminho}`, metodo === "excluir" ? undefined : {})
        if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
      this.carregar()
    },

    confirmar() {
      this.executar("enviar", "confirmar")
    },

    descartar() {
      this.executar("excluir", "descartar")
    }
  })
})
