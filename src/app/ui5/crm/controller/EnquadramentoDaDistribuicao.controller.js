// Enquadramento da distribuição (14, R342 a R347): incluir e editar em modal pequeno; mover e excluir pelo menu da linha; todos devolvem o endereço
// da conferência do impacto, que abre numa aba. Tempo real pelo recurso `credores`.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario",
  "crm/servico/tempo-real"],
  (Controller, JSONModel, Menu, MenuItem, MessageBox, http, formulario, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.EnquadramentoDaDistribuicao", {
    onInit() {
      this.credor = this.getView().getViewData()?.argumentos?.["?filtro"]?.tenant_id || ""
      this.getView().setModel(new JSONModel({ credores: [], itens: [] }), "dados")
      this.getView().setModel(new JSONModel({ detalhe: null }), "ui")
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => { if (mensagem.acao !== "atualizar" || mensagem.registros.some((credor) => String(credor.id) === this.credor)) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const dados = await http.obter(`/operacoes/enquadramento-da-distribuicao.json?tenant_id=${encodeURIComponent(this.credor)}`)
      this.credor = dados.credor_id
      this.getView().getModel("dados").setData(dados)
    },

    mudarCredor(evento) {
      this.credor = evento.getParameter("item").getKey()
      this.carregar()
    },

    mostrarDetalhe(evento) {
      this.getView().getModel("ui").setProperty("/detalhe", evento.getParameter("listItem").getBindingContext("dados").getObject())
    },

    conferir(resposta) {
      const endereco = new URL(resposta.destino, window.location.origin)
      this.getOwnerComponent().getRouter().navTo("conferenciaDaDistribuicao", { "?filtro": { tenant_id: this.credor, token: endereco.searchParams.get("token") } })
    },

    campoDasOperacoes(escolhas) {
      return { nome: "operation_ids", rotulo: this.texto("distribuicao.operacoes"), tipo: "varios", opcoes: escolhas.operacoes, valor: escolhas.item?.operacoes || [],
        ajuda: escolhas.exclusiva ? this.texto("distribuicao.enquadramento.exclusiva") : null }
    },

    async incluir() {
      const escolhas = await http.obter(`/operacoes/enquadramento-da-distribuicao/incluir.json?tenant_id=${this.credor}`)
      if (!escolhas.segmentos.length) return MessageBox.information(this.texto("enquadramento.semSegmento"))
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("distribuicao.enquadramento.incluir"), descricao: this.texto("distribuicao.enquadramento.incluir.ajuda"),
        escopo: "rule", url: `/operacoes/enquadramento-da-distribuicao?tenant_id=${this.credor}`, botao: this.texto("enquadramento.conferir"),
        campos: [
          { nome: "segment_id", rotulo: this.texto("enquadramento.segmento"), tipo: "opcoes", opcoes: escolhas.segmentos },
          this.campoDasOperacoes(escolhas),
          { nome: "exposure", rotulo: this.texto("distribuicao.exposicao"), tipo: "opcoes", opcoes: escolhas.exposicoes },
          { nome: "position", rotulo: this.texto("enquadramento.posicao"), tipo: "opcoes", opcoes: escolhas.posicoes, valor: escolhas.posicoes.at(-1)?.id }
        ]
      }).then((resposta) => this.conferir(resposta))
    },

    async editar(item) {
      const escolhas = await http.obter(`/operacoes/enquadramento-da-distribuicao/${item.indice}/editar.json?tenant_id=${this.credor}`)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("enquadramento.editar.titulo", [item.segmento]), escopo: "rule", metodo: "PATCH",
        url: `/operacoes/enquadramento-da-distribuicao/${item.indice}?tenant_id=${this.credor}`, botao: this.texto("enquadramento.conferir"),
        campos: [this.campoDasOperacoes(escolhas), { nome: "exposure", rotulo: this.texto("distribuicao.exposicao"), tipo: "opcoes", opcoes: escolhas.exposicoes, valor: escolhas.item?.exposicao }]
      }).then((resposta) => this.conferir(resposta))
    },

    async executar(metodo, url) {
      try {
        this.conferir(await http[metodo](url, metodo === "excluir" ? undefined : {}))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    acoes(evento) {
      const item = evento.getSource().getBindingContext("dados").getObject()
      const base = `/operacoes/enquadramento-da-distribuicao/${item.indice}`
      const itens = [new MenuItem({ text: this.texto("acao.editar"), press: () => this.editar(item) })]
      if (!item.primeiro) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaCima"), press: () => this.executar("enviar", `${base}/mover?tenant_id=${this.credor}&offset=-1`) }))
      if (!item.ultimo) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaBaixo"), press: () => this.executar("enviar", `${base}/mover?tenant_id=${this.credor}&offset=1`) }))
      itens.push(new MenuItem({ text: this.texto("acao.excluir"), press: () => this.executar("excluir", `${base}?tenant_id=${this.credor}`) }))
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
