// Índices do Banco Central (08, R145 a R147): o JSON da mesma rota, com a página dos meses em `?filtro`; "Buscar índices agora" pela rota de sempre;
// editar índice (quatro campos) no painel lateral; desfazer a correção (o motivo) em modal pequeno. Tempo real: refaz quando chega aviso do recurso
// `credores` e na reconexão (a busca terminada ainda não publica aviso na SPA; ver as notas do porte).
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/MessageToast", "sap/m/MessageBox",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/painel", "crm/servico/gravar", "crm/servico/tempo-real"],
  (Controller, JSONModel, formatMessage, MessageToast, MessageBox, http, formulario, painel, gravar, tempoReal) => {
  "use strict"

  const SEM_DETALHE = { credor_id: null, mes: "", itens: [] }

  return Controller.extend("crm.controller.Indices", {
    formatarTexto: formatMessage,

    onInit() {
      this.pagina = Number(this.getView().getViewData()?.argumentos?.["?filtro"]?.page) || 1
      this.getView().setModel(new JSONModel({ credores: [], buscas: [], series: [], pagina: 1, paginas: 1 }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false, detalhe: { ...SEM_DETALHE } }), "ui")
      this.desligar = [tempoReal.ouvir("credores", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const view = this.getView()
      view.setBusy(true)
      try {
        const dados = await http.obter(`/configuracao/indices.json?page=${this.pagina}`)
        this.pagina = dados.pagina
        view.getModel("dados").setData(dados)
        this.atualizarDetalhe(dados)
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      } finally {
        view.setBusy(false)
      }
    },

    // Depois de recarregar, o detalhe aberto mostra os dados novos do mesmo mês (ou fecha, se o mês saiu da página).
    atualizarDetalhe(dados) {
      const ui = this.getView().getModel("ui")
      const aberto = ui.getProperty("/detalhe")
      const mes = dados.credores.find((credor) => credor.id === aberto.credor_id)?.meses.find((linha) => linha.mes === aberto.mes)
      ui.setProperty("/detalhe", mes ? { credor_id: aberto.credor_id, mes: mes.mes, itens: mes.detalhe } : { ...SEM_DETALHE })
    },

    mostrarDetalhe(evento) {
      const mes = evento.getParameter("listItem").getBindingContext("dados").getObject()
      const ui = this.getView().getModel("ui")
      const igual = ui.getProperty("/detalhe/credor_id") === mes.credor_id && ui.getProperty("/detalhe/mes") === mes.mes
      // Tocar de novo na mesma linha fecha o detalhe.
      ui.setProperty("/detalhe", igual ? { ...SEM_DETALHE } : { credor_id: mes.credor_id, mes: mes.mes, itens: mes.detalhe })
    },

    mesesMaisNovos() {
      this.pagina = Math.max(1, this.pagina - 1)
      this.carregar()
    },

    mesesAnteriores() {
      this.pagina += 1
      this.carregar()
    },

    buscarAgora() {
      gravar(this, "enviar", "/configuracao/busca-de-indices", {})
    },

    editarIndice(evento) {
      const credor = evento.getSource().getBindingContext("dados").getObject()
      const series = this.getView().getModel("dados").getProperty("/series")
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("indices.editar"), descricao: credor.nome,
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "adjustment",
        url: `/configuracao/correcoes-de-indices?tenant_id=${credor.id}`, botao: this.texto("indices.salvarIndice"),
        campos: [
          { nome: "series", rotulo: this.texto("indices.serie"), tipo: "opcoes", opcoes: series, valor: series[0]?.id },
          { nome: "month", rotulo: this.texto("indices.mesAno"), tipo: "texto", obrigatorio: true, max: 7, ajuda: this.texto("indices.mesAno.ajuda") },
          { nome: "value", rotulo: this.texto("indices.valor"), tipo: "valor", obrigatorio: true, ajuda: this.texto("indices.valor.ajuda") },
          { nome: "reason", rotulo: this.texto("indices.motivoDaCorrecao"), tipo: "texto", obrigatorio: true, max: 300 }
        ]
      }).then((resposta) => {
        if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.carregar()
      })
    },

    // Desfazer a correção: um campo (o motivo), em modal pequeno.
    desfazer(evento) {
      const item = evento.getSource().getBindingContext("ui").getObject()
      const mes = this.getView().getModel("ui").getProperty("/detalhe/mes")
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("indices.desfazer.titulo"), descricao: this.texto("indices.desfazer.ajuda", [item.serie, mes]),
        escopo: "adjustment", url: `/configuracao/correcoes-de-indices/${item.correcao_id}`, metodo: "DELETE", botao: this.texto("indices.desfazer.botao"), perigoso: true,
        campos: [{ nome: "reason", rotulo: this.texto("indices.motivo"), tipo: "texto", obrigatorio: true, max: 300 }]
      }).then((resposta) => {
        if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.carregar()
      })
    }
  })
})
