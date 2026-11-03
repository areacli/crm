// Página do acordo (11): o JSON da mesma rota do Rails; o título da aba é o número do acordo (P27). As ações usam as rotas de sempre; o aceite,
// formulário médio, vai ao painel lateral da aba. Tempo real: a página se refaz quando o acordo muda (recurso `clientes`, do cliente do acordo).
sap.ui.define([
  "sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "sap/base/strings/formatMessage",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/tempo-real"
], (Controller, JSONModel, Menu, MenuItem, MessageToast, MessageBox, formatMessage, http, formulario, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Acordo", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ selos: [], avisos: [], titulos: { colunas: [], linhas: [] }, parcelas: [], titulos_de_acordo: [], titulos_de_estorno: [], historico: [], condicoes: [], aceite: [], quitacoes: [], pode: {} }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      this.carregar()
      this.desligar = [
        tempoReal.ouvir("clientes", (mensagem) => {
          const ids = [...(mensagem.registros || []).map((cliente) => cliente.id), ...(mensagem.removidos || [])]
          if (mensagem.acao === "recarregar" || ids.includes(this.getView().getModel("dados").getProperty("/cliente_id"))) this.carregar()
        }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave, ...valores) {
      return formatMessage(this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave), valores)
    },

    async carregar() {
      try {
        const dados = await http.obter(`/acordos/${this.id}.json`)
        this.getView().getModel("dados").setData(dados)
        this.aba?.setName(this.texto("acordo.titulo", dados.numero))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || this.texto(erro.status === 404 ? "erro.naoEncontrado" : "erro.geral"))
      }
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    async executar(url, metodo = "POST") {
      try {
        this.concluir(await http[{ POST: "enviar", PATCH: "alterar", DELETE: "excluir" }[metodo]](url, {}))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    abrirFormulario(definicao) {
      return formulario.abrir({ textoCancelar: this.texto("acao.cancelar"), ...definicao }).then((resposta) => this.concluir(resposta))
    },

    motivo(chave) {
      return { nome: "reason", rotulo: this.texto(chave), tipo: "texto", obrigatorio: true, max: 300 }
    },

    abrirFicha() {
      this.getOwnerComponent().getRouter().navTo("cliente", { id: String(this.getView().getModel("dados").getProperty("/cliente_id")) })
    },

    abrirTermo() {
      window.open(`/acordos/${this.id}/termo`, "_blank", "noopener")
    },

    aprovar() {
      this.executar(`/acordos/${this.id}/aprovacao`)
    },

    // Painel lateral (regra de ação): a página vai à segunda coluna, e a lateral de condições dá lugar a ela.
    painel() {
      const colunas = this.byId("colunas")
      const ui = this.getView().getModel("ui")
      return {
        mostrar: (pagina) => { colunas.addMidColumnPage(pagina); colunas.toMidColumnPage(pagina); colunas.setLayout("TwoColumnsBeginExpanded"); ui.setProperty("/painelAberto", true) },
        fechar: (pagina) => { colunas.removeMidColumnPage(pagina); colunas.setLayout("OneColumn"); ui.setProperty("/painelAberto", false) }
      }
    },

    async registrarAceite() {
      const dados = await http.obter(`/acordos/${this.id}/aceite/new.json`)
      this.abrirFormulario({
        titulo: this.texto("acordo.registrarAceite"), descricao: this.texto("acordo.aceite.ajuda"), aviso: dados.aviso, emPainel: this.painel(), escopo: "acceptance",
        url: `/acordos/${this.id}/aceite`, botao: this.texto("acordo.registrarAceite"),
        campos: [
          { nome: "presented_channel", rotulo: this.texto("acordo.aceite.canalDaApresentacao"), tipo: "opcoes", opcoes: dados.canais },
          { nome: "presented_at", rotulo: this.texto("acordo.aceite.quandoApresentado"), tipo: "dataEHora", obrigatorio: true },
          { nome: "accepted_channel", rotulo: this.texto("acordo.aceite.canalDoAceite"), tipo: "opcoes", opcoes: dados.canais },
          { nome: "accepted_at", rotulo: this.texto("acordo.aceite.quandoAceito"), tipo: "dataEHora", obrigatorio: true },
          { nome: "accepted_by_customer_id", rotulo: this.texto("acordo.aceite.quem"), tipo: "opcoes", opcoes: dados.aceitantes },
          { nome: "proof", rotulo: this.texto("acordo.aceite.comprovante"), tipo: "texto", max: 200, ajuda: this.texto("acordo.aceite.comprovante.ajuda") }
        ]
      })
    },

    maisAcoes(evento) {
      const pode = this.getView().getModel("dados").getProperty("/pode")
      const numero = this.getView().getModel("dados").getProperty("/numero")
      const comMotivo = (chave, caminho, escopo, rotulo, descricao) => this.abrirFormulario({
        titulo: this.texto(chave), descricao: descricao || this.texto("acordo.titulo", numero), perigoso: true, escopo, url: `/acordos/${this.id}/${caminho}`, botao: this.texto(chave), campos: [this.motivo(rotulo)]
      })
      const confirmar = (chave, mensagem, metodo, perigoso) => MessageBox.confirm(this.texto(mensagem), {
        title: this.texto(chave), actions: [this.texto(chave), MessageBox.Action.CANCEL], emphasizedAction: perigoso ? null : this.texto(chave),
        onClose: (acao) => acao === this.texto(chave) && this.executar(`/acordos/${this.id}/reversao`, metodo)
      })
      const itens = [
        pode.recusar && ["acordo.recusar", () => comMotivo("acordo.recusar", "recusa", "agreement", "acordo.motivoDaRecusa", this.texto("acordo.recusar.ajuda", numero))],
        pode.cancelar && ["acordo.cancelar", () => comMotivo("acordo.cancelar", "cancelamento", "agreement", "acordo.motivoDoCancelamento")],
        pode.quitar && ["acordo.calcularQuitacao", () => this.abrirFormulario({
          titulo: this.texto("acordo.calcularQuitacao"), descricao: this.texto("acordo.quitacao.ajuda", numero), escopo: "settlement", url: `/acordos/${this.id}/quitacao`,
          botao: this.texto("acordo.calcularQuitacao"), campos: [{ nome: "on_date", rotulo: this.texto("acordo.dataDaQuitacao"), tipo: "data", obrigatorio: true, valor: new Date().toISOString().slice(0, 10) }]
        })],
        pode.quebrar && ["acordo.quebrar", () => this.abrirFormulario({
          titulo: this.texto("acordo.quebrar"), descricao: this.texto("acordo.quebrar.ajuda"), perigoso: true, escopo: "break", url: `/acordos/${this.id}/quebra`, botao: this.texto("acordo.quebrar"),
          campos: [this.motivo("acordo.motivoDaQuebra"), { nome: "fraud", rotulo: this.texto("acordo.quebraPorFraude"), tipo: "marca" }]
        })],
        pode.reverter && ["acordo.reverter", () => this.abrirFormulario({
          titulo: this.texto("acordo.reverter"), descricao: this.texto("acordo.reverter.ajuda", numero), perigoso: true, escopo: "reversion", url: `/acordos/${this.id}/reversao`,
          botao: this.texto("acordo.abrirReversao"), campos: [this.motivo("acordo.motivoDaReversao")]
        })],
        pode.concluir && ["acordo.concluirReversao", () => confirmar("acordo.concluirReversao", "acordo.concluirReversao.mensagem", "PATCH", true)],
        pode.concluir && ["acordo.desistirReversao", () => confirmar("acordo.desistirReversao", "acordo.desistirReversao.mensagem", "DELETE", false)]
      ].filter(Boolean)
      const menu = new Menu({ items: itens.map(([chave, acao]) => new MenuItem({ text: this.texto(chave), press: acao })), closed: () => setTimeout(() => menu.destroy()) })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
