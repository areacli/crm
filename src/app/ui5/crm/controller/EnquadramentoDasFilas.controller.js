// Enquadramento das filas (15, R349, R357): incluir e editar item em modal pequeno; mover e excluir são botões do menu da linha; os quatro devolvem o
// endereço da conferência do impacto, que abre numa aba. Ordem e tempos (valem na hora) no painel lateral. Tempo real pelo recurso `credores`.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/painel", "crm/servico/tempo-real"],
  (Controller, JSONModel, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.EnquadramentoDasFilas", {
    onInit() {
      this.credor = this.getView().getViewData()?.argumentos?.["?filtro"]?.tenant_id || ""
      this.getView().setModel(new JSONModel({ credores: [], enquadramentos: [] }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
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
      const dados = await http.obter(`/filas/enquadramento.json?tenant_id=${encodeURIComponent(this.credor)}`)
      this.credor = dados.credor_id
      this.getView().getModel("dados").setData(dados)
    },

    mudarCredor(evento) {
      this.credor = evento.getParameter("item").getKey()
      this.carregar()
    },

    contexto(evento) {
      return evento.getSource().getBindingContext("dados")
    },

    // O sujeito do cartão da linha (o caminho do item é /enquadramentos/N/itens/M).
    sujeito(contexto) {
      return this.getView().getModel("dados").getProperty(contexto.getPath().split("/itens/")[0] + "/sujeito")
    },

    // Mudanças no enquadramento devolvem o endereço da conferência: ela abre numa aba.
    conferir(resposta) {
      const endereco = new URL(resposta.destino, window.location.origin)
      this.getOwnerComponent().getRouter().navTo("conferenciaDasFilas", { "?filtro": { tenant_id: this.credor, token: endereco.searchParams.get("token") } })
    },

    campos(escolhas, comPosicao) {
      const campos = [
        { nome: "name", rotulo: this.texto("enquadramento.nome"), tipo: "texto", obrigatorio: true, max: 100, valor: escolhas.item?.nome },
        { nome: "segment_id", rotulo: this.texto("enquadramento.segmento"), tipo: "opcoes", opcoes: escolhas.segmentos, valor: escolhas.item?.segmento_id },
        { nome: "delivers", rotulo: this.texto("filas.entrega"), tipo: "opcoes", valor: escolhas.item && !escolhas.item.entrega ? "0" : "1",
          opcoes: [{ id: "1", nome: this.texto("filas.entrega.sim") }, { id: "0", nome: this.texto("filas.entrega.nao") }] }
      ]
      if (comPosicao) campos.push({ nome: "position", rotulo: this.texto("enquadramento.posicao"), tipo: "opcoes", opcoes: escolhas.posicoes, valor: escolhas.posicoes.at(-1)?.id })
      return campos
    },

    async incluir(evento) {
      const contexto = this.contexto(evento)
      const sujeito = contexto.getProperty("sujeito")
      const base = `/filas/enquadramento?tenant_id=${this.credor}&sujeito=${sujeito}`
      const escolhas = await http.obter(`/filas/enquadramento/incluir.json?tenant_id=${this.credor}&sujeito=${sujeito}`)
      if (!escolhas.segmentos.length) return MessageBox.information(this.texto("enquadramento.semSegmento"))
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("enquadramento.incluir.titulo", [contexto.getProperty("nome").toLowerCase()]),
        descricao: this.texto("enquadramento.incluir.ajuda"), escopo: "queue", url: base, botao: this.texto("enquadramento.conferir"), campos: this.campos(escolhas, true)
      }).then((resposta) => this.conferir(resposta))
    },

    async editarItem(contexto) {
      const item = contexto.getObject()
      const sujeito = this.sujeito(contexto)
      const escolhas = await http.obter(`/filas/enquadramento/${item.indice}/editar.json?tenant_id=${this.credor}&sujeito=${sujeito}`)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("enquadramento.editar.titulo", [item.nome]), escopo: "queue", metodo: "PATCH",
        url: `/filas/enquadramento/${item.indice}?tenant_id=${this.credor}&sujeito=${sujeito}`, botao: this.texto("enquadramento.conferir"), campos: this.campos(escolhas, false)
      }).then((resposta) => this.conferir(resposta))
    },

    async executar(metodo, url) {
      try {
        this.conferir(await http[metodo](url, metodo === "excluir" ? undefined : {}))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    async ordemETempos(item) {
      const fila = await http.obter(`/filas/ajustes/${item.id}/editar.json`)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("filas.ordemETempos.titulo", [fila.nome]), descricao: this.texto("filas.ordemETempos.ajuda"),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "queue", url: `/filas/ajustes/${item.id}`, metodo: "PATCH", botao: this.texto("acao.salvar"),
        campos: [
          { nome: "order_by", rotulo: this.texto("filas.criterio"), tipo: "opcoes", opcoes: fila.ordens, valor: fila.ordem },
          { nome: "order_tiebreak", rotulo: this.texto("filas.desempate"), tipo: "opcoes", opcoes: [{ id: "", nome: this.texto("filas.nenhum") }, ...fila.ordens], valor: fila.desempate },
          { nome: "lock_minutes", rotulo: this.texto("filas.trava"), tipo: "numero", valor: fila.trava, obrigatorio: true },
          { nome: "intervalos", rotulo: this.texto("filas.intervalos"), tipo: "grupo" },
          { nome: "interval_no_contact_hours", rotulo: this.texto("filas.semContato"), tipo: "numero", valor: fila.sem_contato },
          { nome: "interval_third_party_hours", rotulo: this.texto("filas.terceiro"), tipo: "numero", valor: fila.terceiro },
          { nome: "interval_customer_hours", rotulo: this.texto("filas.cliente"), tipo: "numero", valor: fila.cliente, ajuda: this.texto("filas.intervalos.ajuda") }
        ]
      }).then((resposta) => { MessageToast.show(resposta.mensagem || "", { duration: 6000 }); this.carregar() })
    },

    acoes(evento) {
      const contexto = this.contexto(evento)
      const item = contexto.getObject()
      const sujeito = this.sujeito(contexto)
      const consulta = `tenant_id=${this.credor}&sujeito=${sujeito}`
      const itens = []
      if (item.entrega) itens.push(new MenuItem({ text: this.texto("filas.ordemETempos"), press: () => this.ordemETempos(item) }))
      if (!item.trilha_padrao) {
        itens.push(new MenuItem({ text: this.texto("enquadramento.editar"), press: () => this.editarItem(contexto) }))
        if (!item.primeiro) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaCima"), press: () => this.executar("enviar", `/filas/enquadramento/${item.indice}/mover?${consulta}&offset=-1`) }))
        if (!item.ultimo) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaBaixo"), press: () => this.executar("enviar", `/filas/enquadramento/${item.indice}/mover?${consulta}&offset=1`) }))
        itens.push(new MenuItem({ text: this.texto("acao.excluir"), press: () => this.executar("excluir", `/filas/enquadramento/${item.indice}?${consulta}`) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
