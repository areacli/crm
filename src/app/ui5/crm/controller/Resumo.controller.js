// Resumo da carteira (R23): o JSON da mesma rota do Rails. Tempo real: o resumo se refaz quando a conexão volta e quando um acionamento,
// promessa ou acordo muda (recurso `clientes`), no máximo uma vez a cada 5 s.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Popover", "sap/m/Text", "crm/servico/http", "crm/servico/tempo-real"],
  (Controller, JSONModel, Popover, Text, http, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Resumo", {
    onInit() {
      this.getView().setModel(new JSONModel({ vazio: false }), "dados")
      this.carregar()
      this.desligar = [tempoReal.ouvir("*conectado", () => this.carregarDepois()), tempoReal.ouvir("clientes", () => this.carregarDepois())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // Muitos avisos seguidos (uma carga, uma tarefa diária) refazem o resumo uma vez só.
    carregarDepois() {
      clearTimeout(this.espera)
      this.espera = setTimeout(() => this.carregar(), 5000)
    },

    async carregar() {
      this.getView().getModel("dados").setData(await http.obter("/resumo.json"))
    },

    // O (i) abre a definição num popover (design system, revisão 4: a definição fica fora da tela).
    mostrarDefinicao(evento) {
      const botao = evento.getSource()
      const popover = new Popover({ title: botao.getTooltip(), contentWidth: "20rem", content: [new Text({ text: botao.data("definicao") }).addStyleClass("sapUiSmallMargin")], afterClose: () => popover.destroy() })
      popover.openBy(botao)
    }
  })
})
