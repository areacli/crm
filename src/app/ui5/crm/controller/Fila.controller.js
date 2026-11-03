// Uma fila (15, R357): a lista da mesma rota, no credor da fila. Tempo real: refaz quando as filas do credor mudam (recurso `credores`).
sap.ui.define(["crm/controller/Lista", "crm/servico/tempo-real", "crm/servico/liberar-entrega"], (Lista, tempoReal, liberarEntrega) => {
  "use strict"

  return Lista.extend("crm.controller.Fila", {
    filtroInicial: { tenant_id: "", per_page: 20, page: 1 },

    onInit() {
      this.endereco = `/filas/${this.getView().getViewData().argumentos.id}`
      Lista.prototype.onInit.apply(this, arguments)
      const credor = () => String(this.getView().getModel("dados").getProperty("/credor_id"))
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => { if (mensagem.acao !== "atualizar" || mensagem.registros.some((item) => String(item.id) === credor())) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    aoCarregar(dados) {
      this.getView().getViewData().aba?.setName(dados.nome)
    },

    liberar(evento) {
      liberarEntrega(this.objetoDaLinha(evento).entrega_id).then(() => this.carregar())
    }
  })
})
