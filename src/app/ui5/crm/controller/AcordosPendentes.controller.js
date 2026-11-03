// Acordos pendentes (11, R243): aprovar é botão direto; recusar pede o motivo num modal pequeno. Tempo real: a lista se refaz quando um acordo
// muda (recurso `clientes`, publicado pelo acordo).
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario", "crm/servico/tempo-real"],
  (Lista, Menu, MenuItem, MessageToast, MessageBox, http, formulario, tempoReal) => {
  "use strict"

  return Lista.extend("crm.controller.AcordosPendentes", {
    endereco: "/acordos/pendentes",
    filtroInicial: { tenant: "", per_page: 10, page: 1 },
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

    abrirAcordo(evento) {
      this.navegar("acordo", { id: String(this.objetoDaLinha(evento).id) })
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    async aprovar(evento) {
      try {
        const resposta = await http.enviar(`/acordos/${this.objetoDaLinha(evento).id}/aprovacao`, {})
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.carregar()
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    acoes(evento) {
      const acordo = this.objetoDaLinha(evento)
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("pendentes.acordos.abrir"), press: () => this.navegar("acordo", { id: String(acordo.id) }) }),
        new MenuItem({ text: this.texto("acordo.recusar"), press: () => formulario.abrir({
          textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("acordo.recusar"), descricao: acordo.numero, perigoso: true, escopo: "agreement",
          url: `/acordos/${acordo.id}/recusa`, botao: this.texto("acordo.recusar"), campos: [{ nome: "reason", rotulo: this.texto("acordo.motivoDaRecusa"), tipo: "texto", obrigatorio: true, max: 300 }]
        }).then((resposta) => { MessageToast.show(resposta.mensagem || ""); this.carregar() }) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
