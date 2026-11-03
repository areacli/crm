// Editor do segmento (13, R285, R288, R301 a R305): criar (em branco, de um exemplo ou cópia de outro, "Duplicar") e editar. O texto vai ao rascunho
// a cada pausa de 600 ms na digitação e a coluna "Como fica" se refaz com a leitura e os erros de cada linha (a caixa não é refeita: o cursor fica
// onde estava). "Conferir" roda em segundo plano: a tela busca o resultado uma vez logo depois e de novo a cada aviso do tempo real (recurso
// `credores`) ou reconexão, enquanto conta, sem polling. Salvar envia às rotas de sempre; em uso no enquadramento, a resposta leva à conferência do impacto.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "sap/ui/core/InvisibleMessage",
  "sap/ui/core/library", "crm/servico/http", "crm/servico/tempo-real", "crm/controller/SegmentosDestino"],
  (Controller, JSONModel, MessageToast, MessageBox, InvisibleMessage, coreLibrary, http, tempoReal, destino) => {
  "use strict"

  const ESPERA_DO_RASCUNHO = 600
  const LISTA = "/configuracao/segmentos"

  return Controller.extend("crm.controller.EditorDeSegmento", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.aba = aba
      this.argumentos = argumentos || {}
      this.trabalho = false
      this.pedidoDoRascunho = 0
      this.getView().setModel(new JSONModel({ como_fica: { escrito: false, linhas: [] }, conferir: {}, exemplos: [], usos: [] }), "dados")
      this.getView().setModel(new JSONModel({ erro: "", enviando: false }), "ui")
      this.desligar = [
        tempoReal.ouvir("credores", () => this.buscarConferencia()),
        tempoReal.ouvir("*conectado", () => this.buscarConferencia())
      ]
      this.carregar()
    },

    onExit() {
      clearTimeout(this.espera)
      clearTimeout(this.esperaDaConferencia)
      this.desligar?.forEach((desligar) => desligar())
    },

    // A aba não se fecha sozinha com texto por salvar (P27).
    temTrabalho() {
      return this.trabalho
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    modelo() {
      return this.getView().getModel("dados")
    },

    id() {
      return this.argumentos.id
    },

    filtro() {
      return this.argumentos["?filtro"] || {}
    },

    // Mesmos parâmetros da página do servidor: credor, cópia de outro segmento ou exemplo.
    enderecoDoNovo(exemplo) {
      const parametros = new URLSearchParams({ tenant_id: this.filtro().tenant_id || "" })
      if (this.filtro().from) parametros.set("from", this.filtro().from)
      if (exemplo) parametros.set("exemplo", exemplo)
      return `${LISTA}/novo.json?${parametros}`
    },

    async carregar(exemplo) {
      const view = this.getView()
      view.setBusy(true)
      try {
        const dados = await http.obter(this.id() ? `${LISTA}/${this.id()}/editar.json` : this.enderecoDoNovo(exemplo))
        this.modelo().setData(dados)
        this.getView().getModel("ui").setProperty("/erro", "")
        this.trabalho = Boolean(exemplo)
        this.aba?.setName(dados.sujeito_fixo ? this.texto("segmentos.editar.aba", [dados.nome]) : this.texto("segmentos.novo.titulo"))
      } catch (erro) {
        MessageBox.error(erro.status === 404 ? this.texto("segmentos.naoEncontrado") : erro.corpo?.mensagem || erro.message)
      } finally {
        view.setBusy(false)
      }
    },

    // Os exemplos (R290) só preenchem o editor; nada é salvo até salvar.
    usarExemplo(evento) {
      this.carregar(evento.getSource().getBindingContext("dados").getProperty("id"))
    },

    // O que vai ao servidor, no escopo de parâmetros da ação, e a consulta com o segmento e o credor (como o formulário da página do servidor).
    corpo() {
      return { segment: { name: this.modelo().getProperty("/nome") || "", source: this.modelo().getProperty("/texto") || "" } }
    },

    consulta() {
      const parametros = new URLSearchParams({ tenant_id: this.modelo().getProperty("/credor_id") || "" })
      if (this.modelo().getProperty("/id")) parametros.set("id", this.modelo().getProperty("/id"))
      return parametros.toString()
    },

    marcarTrabalho() {
      this.trabalho = true
    },

    aoEscrever(evento) {
      this.trabalho = true
      // O `liveChange` chega antes da gravação no modelo: guarda o texto já, para o rascunho mandar o que está na caixa.
      this.modelo().setProperty("/texto", evento.getParameter("value"))
      clearTimeout(this.espera)
      this.espera = setTimeout(() => this.rascunho(), ESPERA_DO_RASCUNHO)
    },

    // Rascunho (R302): só a coluna "Como fica"; a resposta de um pedido antigo não passa por cima da de um mais novo.
    async rascunho() {
      const pedido = ++this.pedidoDoRascunho
      try {
        const comoFica = await http.enviar(`${LISTA}/rascunho?${this.consulta()}`, this.corpo())
        if (pedido !== this.pedidoDoRascunho) return
        this.modelo().setProperty("/como_fica", comoFica)
        // O texto mudou: o "Conferir" anterior não vale mais (como na página do servidor, que refaz o trecho sem resultado).
        this.conferenciaVazia(comoFica.sujeito)
      } catch (erro) {
        if (pedido === this.pedidoDoRascunho) this.getView().getModel("ui").setProperty("/erro", erro.corpo?.mensagem || erro.message)
      }
    },

    conferenciaVazia(sujeito) {
      clearTimeout(this.esperaDaConferencia)
      this.modelo().setProperty("/conferir", { estado: "vazio", texto: this.texto("segmentos.conferir.vazio", [this.texto(`segmentos.sujeito.${sujeito || "contracts"}`)]) })
    },

    // "Conferir" (R288, revisão 3): o servidor guarda o pedido e responde "Contando…" com o id; o resultado vem quando o job termina.
    async conferir() {
      clearTimeout(this.espera)
      try {
        const resultado = await http.enviar(`${LISTA}/conferir?${this.consulta()}`, this.corpo())
        this.mostrarConferencia(resultado)
        if (resultado.estado === "invalido") this.rascunho()
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    mostrarConferencia(resultado) {
      this.modelo().setProperty("/conferir", resultado)
      if (resultado.estado === "contando") {
        // Uma busca logo depois, para o resultado que já ficou pronto (a página do servidor faz o mesmo ao carregar o trecho).
        clearTimeout(this.esperaDaConferencia)
        this.esperaDaConferencia = setTimeout(() => this.buscarConferencia(), 400)
      } else if (resultado.estado !== "vazio") {
        InvisibleMessage.getInstance().announce(resultado.texto, coreLibrary.InvisibleMessageMode.Polite)
      }
    },

    async buscarConferencia() {
      const atual = this.modelo().getProperty("/conferir")
      if (atual?.estado !== "contando" || !atual.id) return
      try {
        const resultado = await http.obter(`${LISTA}/conferir/${encodeURIComponent(atual.id)}`)
        // Só se ainda é a mesma conferência (o texto pode ter mudado no meio).
        if (this.modelo().getProperty("/conferir/id") === atual.id && resultado.estado !== "contando") this.mostrarConferencia(resultado)
      } catch (erro) {
        // O pedido expirou (404): volta ao "Conferir" sem resultado.
        if (erro.status === 404) this.conferenciaVazia(this.modelo().getProperty("/como_fica/sujeito"))
      }
    },

    // Salvar (R303): com erro no texto, o servidor recusa e a coluna "Como fica" mostra os erros de cada linha. Em uso no enquadramento, a
    // resposta é a conferência do impacto (R272), que abre no lugar.
    async salvar() {
      clearTimeout(this.espera)
      const ui = this.getView().getModel("ui")
      ui.setProperty("/enviando", true)
      ui.setProperty("/erro", "")
      try {
        const id = this.modelo().getProperty("/id")
        const resposta = id
          ? await http.alterar(`${LISTA}/${id}`, this.corpo())
          : await http.enviar(`${LISTA}?tenant_id=${encodeURIComponent(this.modelo().getProperty("/credor_id") || "")}`, this.corpo())
        this.trabalho = false
        if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
        if (destino.seguir(this, resposta)) return
        // Gravado: a lista dos segmentos (o destino do servidor); o editor do segmento gravado volta ao texto canônico (R303).
        this.getOwnerComponent().getRouter().navTo("segmentos", {})
        this.getView().getViewData()?.fechar?.()
      } catch (erro) {
        ui.setProperty("/erro", erro.corpo?.mensagem || erro.message)
        this.rascunho()
      } finally {
        ui.setProperty("/enviando", false)
      }
    },

    cancelar() {
      this.trabalho = false
      this.getOwnerComponent().getRouter().navTo("segmentos", {})
      this.getView().getViewData()?.fechar?.()
    },

    abrirGlossario() {
      this.getOwnerComponent().getRouter().navTo("glossarioDosSegmentos", {})
    }
  })
})
