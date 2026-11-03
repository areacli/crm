// Base das telas de lista (modelo Lista, P22): o modelo `filtro` (o que vai na consulta), o modelo `dados` (a resposta JSON da mesma rota
// do Rails), a paginação e a busca com espera curta enquanto se digita. A tela informa `endereco` e, se quiser, `opcoesComTodos`.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "crm/servico/http"], (Controller, JSONModel, formatMessage, http) => {
  "use strict"

  return Controller.extend("crm.controller.Lista", {
    formatarTexto: formatMessage,
    filtroInicial: {},
    opcoesComTodos: [],

    onInit() {
      const argumentos = this.getView().getViewData()?.argumentos || {}
      this.getView().setModel(new JSONModel({ ...this.filtroInicial, ...(argumentos["?filtro"] || {}) }), "filtro")
      this.getView().setModel(new JSONModel({ linhas: [], pagina: 1, paginas: 1, total: 0, filtros: {}, pode: {} }), "dados")
      this.carregar()
    },

    // A aba já aberta recebe um filtro novo pelo endereço (a busca global do cabeçalho, por exemplo).
    mudarArgumentos(argumentos) {
      if (!argumentos["?filtro"]) return
      this.getView().getModel("filtro").setData({ ...this.filtroInicial, ...argumentos["?filtro"] })
      this.carregar()
    },

    // Mesmos parâmetros da página do servidor: o que está no filtro, sem os vazios.
    consulta() {
      const filtro = this.getView().getModel("filtro").getData()
      const parametros = new URLSearchParams()
      Object.entries(filtro).forEach(([chave, valor]) => valor !== "" && valor != null && parametros.set(chave, valor))
      return parametros.toString()
    },

    async carregar() {
      const view = this.getView()
      view.setBusy(true)
      try {
        const dados = await http.obter(`${this.endereco}.json?${this.consulta()}`)
        const i18n = this.getOwnerComponent().getModel("i18n").getResourceBundle()
        // Selects com a opção "Todos" ou "Todas" no começo (o valor vazio não filtra).
        this.opcoesComTodos.forEach(([caminho, texto]) => {
          const lista = caminho.split("/").reduce((objeto, chave) => objeto?.[chave], dados)
          if (Array.isArray(lista)) lista.unshift({ id: "", nome: i18n.getText(texto) })
        })
        view.getModel("dados").setData(dados)
        this.aoCarregar?.(dados)
      } catch (erro) {
        sap.ui.require(["sap/m/MessageBox"], (MessageBox) => MessageBox.error(erro.corpo?.mensagem || erro.message))
      } finally {
        view.setBusy(false)
      }
    },

    buscar() {
      this.getView().getModel("filtro").setProperty("/page", 1)
      this.carregar()
    },

    buscarAoDigitar(evento) {
      clearTimeout(this.espera)
      this.getView().getModel("filtro").setProperty("/q", evento.getParameter("newValue"))
      this.espera = setTimeout(() => this.buscar(), 300)
    },

    mudarPorPagina(evento) {
      this.getView().getModel("filtro").setProperty("/per_page", Number(evento.getParameter("selectedItem").getKey()))
      this.buscar()
    },

    paginaAnterior() {
      const filtro = this.getView().getModel("filtro")
      filtro.setProperty("/page", Math.max(1, (filtro.getProperty("/page") || 1) - 1))
      this.carregar()
    },

    proximaPagina() {
      const filtro = this.getView().getModel("filtro")
      filtro.setProperty("/page", (filtro.getProperty("/page") || 1) + 1)
      this.carregar()
    },

    // Abre outra tela da SPA numa aba (P27).
    navegar(rota, argumentos) {
      this.getOwnerComponent().getRouter().navTo(rota, argumentos)
    },

    objetoDaLinha(evento) {
      return evento.getSource().getBindingContext("dados").getObject()
    }
  })
})
