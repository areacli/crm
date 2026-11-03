// Lista de acionamentos (R78): a mesma consulta da página do servidor, em JSON. Tempo real: um acionamento novo de qualquer operador refaz a
// página atual (recurso `clientes`, que o acionamento publica), como fazia o trecho do htmx.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "crm/servico/tempo-real"], (Lista, JSONModel, tempoReal) => {
  "use strict"

  return Lista.extend("crm.controller.Acionamentos", {
    endereco: "/acionamentos",
    filtroInicial: { from: "", to: "", operator: "", channel: "", result: "", kind: "", origin: "", tenant: "", per_page: 10, page: 1 },
    opcoesComTodos: [["filtros/operadores", "filtro.todos"], ["filtros/canais", "filtro.todos"], ["filtros/resultados", "filtro.todos"], ["filtros/tipos", "filtro.todos"],
      ["filtros/origens", "filtro.todas"], ["filtros/credores", "filtro.todos"]],

    onInit() {
      this.getView().setModel(new JSONModel({ detalhe: null }), "ui")
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("clientes", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // O período que o servidor aplicou (o padrão de 7 dias, ou o corte em 92) volta aos campos de data.
    aoCarregar(dados) {
      const filtro = this.getView().getModel("filtro")
      filtro.setProperty("/from", dados.de)
      filtro.setProperty("/to", dados.ate)
    },

    mostrarDetalhe(evento) {
      this.getView().getModel("ui").setProperty("/detalhe", evento.getParameter("listItem").getBindingContext("dados").getObject())
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    }
  })
})
