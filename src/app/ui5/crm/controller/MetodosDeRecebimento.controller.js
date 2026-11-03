// Métodos de recebimento (16, R373): a lista da mesma rota; criar no painel lateral; a linha mostra as integrações no detalhe; o método e a integração
// abrem numa aba.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "crm/servico/http", "crm/servico/formulario", "crm/servico/painel",
  "crm/servico/campos-do-metodo"],
  (Lista, JSONModel, MessageToast, http, formulario, painel, camposDoMetodo) => {
  "use strict"

  return Lista.extend("crm.controller.MetodosDeRecebimento", {
    endereco: "/configuracao/metodos-de-recebimento",
    filtroInicial: { q: "", tenant: "", per_page: 10, page: 1 },
    opcoesComTodos: [["credores", "filtro.todos"]],

    onInit() {
      this.getView().setModel(new JSONModel({ detalhe: null, painelAberto: false }), "ui")
      Lista.prototype.onInit.apply(this, arguments)
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    mostrarDetalhe(evento) {
      this.getView().getModel("ui").setProperty("/detalhe", evento.getParameter("listItem").getBindingContext("dados").getObject())
    },

    abrir(evento) {
      this.navegar("metodoDeRecebimento", { id: String(this.objetoDaLinha(evento).id) })
    },

    abrirIntegracao(evento) {
      this.navegar("integracao", { id: String(evento.getSource().getBindingContext("ui").getProperty("id")) })
    },

    criarIntegracao() {
      this.navegar("novaIntegracao", {})
    },

    async criar() {
      const metodo = await http.obter("/configuracao/metodos-de-recebimento/novo.json")
      const credor = metodo.credores.length > 1
        ? { nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: metodo.credores }
        : { nome: "tenant_id", tipo: "oculto", valor: metodo.credores[0]?.id }
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("metodos.novo"), emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")),
        escopo: "payment_channel", url: "/configuracao/metodos-de-recebimento", botao: this.texto("acao.salvar"), campos: [credor, ...camposDoMetodo((chave) => this.texto(chave), metodo)]
      }).then((resposta) => { MessageToast.show(resposta.mensagem || "", { duration: 6000 }); this.carregar() })
    }
  })
})
