// Distribuição (14, R311, R317, R326): a lista da mesma rota do servidor; distribuir no painel lateral, editar e recolher em modal pequeno,
// todos pelo construtor de formulário, às rotas de sempre.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "crm/servico/formulario", "crm/servico/painel"],
  (Lista, JSONModel, Menu, MenuItem, MessageToast, formulario, painel) => {
  "use strict"

  return Lista.extend("crm.controller.Distribuicao", {
    endereco: "/distribuicao",
    filtroInicial: { q: "", operation: "", status: "", source: "", tenant: "", per_page: 20, page: 1 },
    opcoesComTodos: [["filtros/operacoes", "filtro.todas"], ["filtros/situacoes", "filtro.todas"], ["filtros/origens", "filtro.todas"], ["filtros/credores", "filtro.todos"]],

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

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    distribuirEmLote() {
      this.navegar("novoLote", {})
    },

    concluir(resposta) {
      if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    distribuir() {
      const dados = this.getView().getModel("dados").getData()
      const hoje = new Date().toISOString().slice(0, 10)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("distribuicao.distribuir"), descricao: this.texto("distribuicao.distribuir.ajuda"),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "distribution", url: "/distribuicao", botao: this.texto("distribuicao.distribuir"),
        campos: [
          { nome: "accreditation_id", rotulo: this.texto("distribuicao.operacao"), tipo: "opcoes", opcoes: dados.credenciadas },
          { nome: "target", rotulo: this.texto("distribuicao.oQue"), tipo: "opcoes", opcoes: [{ id: "customer", nome: this.texto("distribuicao.porCliente") }, { id: "contract", nome: this.texto("distribuicao.porContrato") }] },
          { nome: "value", rotulo: this.texto("distribuicao.documentoOuCodigo"), tipo: "texto", obrigatorio: true, max: 100 },
          { nome: "exposure", rotulo: this.texto("distribuicao.exposicao"), tipo: "opcoes", opcoes: dados.exposicoes, valor: dados.exposicao_padrao, ajuda: this.texto("distribuicao.exposicao.ajuda") },
          { nome: "starts_on", rotulo: this.texto("distribuicao.inicio"), tipo: "data", valor: hoje },
          { nome: "ends_on", rotulo: this.texto("distribuicao.fim"), tipo: "data" }
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    editar(distribuicao) {
      const campos = [{ nome: "exposure", rotulo: this.texto("distribuicao.exposicao"), tipo: "opcoes", opcoes: this.getView().getModel("dados").getProperty("/exposicoes"), valor: distribuicao.exposicao_id }]
      campos.push(distribuicao.agendada ? { nome: "starts_on", rotulo: this.texto("distribuicao.inicio"), tipo: "data", valor: distribuicao.inicio } : { nome: "starts_on", tipo: "oculto", valor: distribuicao.inicio })
      campos.push({ nome: "ends_on", rotulo: this.texto("distribuicao.fim"), tipo: "data", valor: distribuicao.fim })
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("distribuicao.editar.titulo", [distribuicao.rotulo]), descricao: this.texto("distribuicao.editar.ajuda", [distribuicao.operacao]),
        escopo: "distribution", url: `/distribuicao/${distribuicao.id}`, metodo: "PATCH", botao: this.texto("acao.salvar"), campos
      }).then((resposta) => this.concluir(resposta))
    },

    recolher(distribuicao) {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("distribuicao.recolher.titulo", [distribuicao.rotulo]), descricao: this.texto("distribuicao.recolher.ajuda", [distribuicao.operacao]),
        perigoso: true, escopo: "recall", url: `/distribuicao/${distribuicao.id}/recolher`, botao: this.texto("distribuicao.recolher"),
        campos: [
          { nome: "reason", rotulo: this.texto("distribuicao.motivo"), tipo: "opcoes", opcoes: this.getView().getModel("dados").getProperty("/motivos_de_recolher"), obrigatorio: true },
          { nome: "note", rotulo: this.texto("distribuicao.observacao"), tipo: "texto", max: 300 },
          { nome: "release_retention", rotulo: this.texto("distribuicao.recolherTambem"), tipo: "marca" }
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    acoes(evento) {
      const distribuicao = this.objetoDaLinha(evento)
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("acao.editar"), press: () => this.editar(distribuicao) }),
        new MenuItem({ text: this.texto("distribuicao.recolher"), press: () => this.recolher(distribuicao) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
