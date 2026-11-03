// Estornos à espera do gestor (11, R233, AH2): a decisão (o que fazer e o motivo) num modal pequeno, com as opções que o estado de cada estorno
// permite. Tempo real: a lista se refaz quando um acordo muda (recurso `clientes`, publicado pelo acordo).
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "crm/servico/formulario", "crm/servico/tempo-real"],
  (Lista, JSONModel, MessageToast, formulario, tempoReal) => {
  "use strict"

  // Base de lista (P22): os que esperam vêm paginados; os decididos há pouco, os 10 últimos.
  return Lista.extend("crm.controller.EstornosAEspera", {
    endereco: "/estornos-a-espera",
    filtroInicial: { per_page: 10, page: 1 },

    onInit() {
      this.getView().setModel(new JSONModel({ detalhe: null }), "ui")
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("clientes", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    mostrarDetalhe(evento) {
      this.getView().getModel("ui").setProperty("/detalhe", evento.getParameter("listItem").getBindingContext("dados").getObject())
    },

    abrirAcordo(evento) {
      this.getOwnerComponent().getRouter().navTo("acordo", { id: String(this.objetoDaLinha(evento).acordo_id) })
    },

    abrirFicha(evento) {
      this.getOwnerComponent().getRouter().navTo("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    async decidir(evento) {
      const estorno = this.objetoDaLinha(evento)
      const resposta = await formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("estornos.decidir.titulo"), descricao: this.texto("estornos.decidir.ajuda", [estorno.pagamento, estorno.valor]),
        escopo: "decision", url: `/estornos-a-espera/${estorno.id}`, metodo: "PATCH", botao: this.texto("estornos.decidir"),
        campos: [{ nome: "choice", rotulo: this.texto("estornos.oQueFazer"), tipo: "opcoes", opcoes: estorno.escolhas },
          { nome: "note", rotulo: this.texto("estornos.motivoDaDecisao"), tipo: "texto", obrigatorio: true, max: 300 }]
      })
      if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    }
  })
})
