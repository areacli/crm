// Guarda de dados (07, R138): o JSON da mesma rota, com uma paginação para os previstos e outra para os retidos; reter e desfazer em modal pequeno,
// com o motivo. Tempo real: refaz quando algo do credor muda (recurso `credores`).
sap.ui.define(["crm/controller/Lista", "sap/m/MessageToast", "crm/servico/formulario", "crm/servico/tempo-real"], (Lista, MessageToast, formulario, tempoReal) => {
  "use strict"

  return Lista.extend("crm.controller.GuardaDeDados", {
    endereco: "/guarda-de-dados",
    filtroInicial: { tenant: "", page: 1, retained_page: 1 },
    opcoesComTodos: [["credores", "filtro.todos"]],

    onInit() {
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("credores", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    paginaDosPrevistos(evento) {
      const filtro = this.getView().getModel("filtro")
      filtro.setProperty("/page", Math.max(1, (filtro.getProperty("/page") || 1) + Number(evento.getSource().data("passo"))))
      this.carregar()
    },

    paginaDosRetidos(evento) {
      const filtro = this.getView().getModel("filtro")
      filtro.setProperty("/retained_page", Math.max(1, (filtro.getProperty("/retained_page") || 1) + Number(evento.getSource().data("passo"))))
      this.carregar()
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).id) })
    },

    motivo(cliente, desfazer) {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto(desfazer ? "guarda.desfazer.titulo" : "guarda.reter.titulo"), descricao: cliente.cliente,
        escopo: "retention", url: `/clientes/${cliente.id}/retencao`, metodo: desfazer ? "DELETE" : "POST", botao: this.texto(desfazer ? "guarda.desfazer.botao" : "guarda.reter.titulo"),
        perigoso: desfazer, campos: [{ nome: "reason", rotulo: this.texto(desfazer ? "distribuicao.motivo" : "guarda.motivoDaRetencao"), tipo: "texto", obrigatorio: true, max: 300,
          ajuda: desfazer ? null : this.texto("guarda.motivoDaRetencao.ajuda") }]
      }).then((resposta) => { MessageToast.show(resposta.mensagem || "", { duration: 6000 }); this.carregar() })
    },

    reter(evento) {
      this.motivo(this.objetoDaLinha(evento), false)
    },

    desfazer(evento) {
      this.motivo(this.objetoDaLinha(evento), true)
    }
  })
})
