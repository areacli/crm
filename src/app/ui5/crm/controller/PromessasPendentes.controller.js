// Promessas pendentes (10, R204): aprovar é botão direto; recusar pede o motivo num modal pequeno. Tempo real: a lista se refaz quando uma
// promessa muda (recurso `clientes`, publicado pela promessa).
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario", "crm/servico/tempo-real"],
  (Lista, Menu, MenuItem, MessageToast, MessageBox, http, formulario, tempoReal) => {
  "use strict"

  return Lista.extend("crm.controller.PromessasPendentes", {
    endereco: "/promessas/pendentes",
    filtroInicial: { tenant: "" },
    opcoesComTodos: [["credores", "filtro.todos"]],

    onInit() {
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("clientes", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    async aprovar(evento) {
      try {
        const resposta = await http.enviar(`/promessas/${this.objetoDaLinha(evento).id}/aprovacao`, {})
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.carregar()
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    acoes(evento) {
      const promessa = this.objetoDaLinha(evento)
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("clientes.abrirFicha"), press: () => this.navegar("cliente", { id: String(promessa.cliente_id) }) }),
        new MenuItem({ text: this.texto("promessa.recusar"), press: () => formulario.abrir({
          textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("promessa.recusar"), descricao: promessa.cliente, perigoso: true, escopo: "promise",
          url: `/promessas/${promessa.id}/recusa`, botao: this.texto("promessa.recusar"), campos: [{ nome: "reason", rotulo: this.texto("ficha.motivo"), tipo: "texto", obrigatorio: true, max: 300 }]
        }).then((resposta) => { MessageToast.show(resposta.mensagem || ""); this.carregar() }) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
