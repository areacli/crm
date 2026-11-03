// Políticas de pagamento (R46, R46a, R62a, R64; 11, R243): o JSON da mesma rota; o cartão de pagamento grava pela rota de sempre e o de crédito e
// tolerância dos acordos pela rota das políticas de acordo, na aba de pagamentos.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Popover", "sap/m/Text", "crm/servico/http", "crm/servico/gravar"],
  (Controller, JSONModel, formatMessage, Popover, Text, http, gravar) => {
  "use strict"

  return Controller.extend("crm.controller.PoliticasDePagamento", {
    formatarTexto: formatMessage,

    onInit() {
      this.getView().setModel(new JSONModel({ credores: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      this.getView().getModel("dados").setData(await http.obter("/configuracao/politicas-de-pagamento.json"))
    },

    credor(evento) {
      const caminho = evento.getSource().getBindingContext("dados").getPath().match(/^\/credores\/\d+/)[0]
      return this.getView().getModel("dados").getProperty(caminho)
    },

    // Marcar uma opção guarda o valor na política (o caminho da opção é .../<política>/opcoes/M).
    escolher(evento) {
      if (!evento.getParameter("selected")) return
      const contexto = evento.getSource().getBindingContext("dados")
      const politica = contexto.getPath().replace(/\/opcoes\/\d+$/, "")
      this.getView().getModel("dados").setProperty(`${politica}/valor`, contexto.getProperty("id"))
    },

    mostrarAjuda(evento) {
      const botao = evento.getSource()
      const politica = botao.getBindingContext("dados").getObject()
      const popover = new Popover({ title: politica.titulo, contentWidth: "22rem", content: [new Text({ text: politica.ajuda }).addStyleClass("sapUiSmallMargin")], afterClose: () => popover.destroy() })
      popover.openBy(botao)
    },

    salvarPagamento(evento) {
      const credor = this.credor(evento)
      const valores = Object.fromEntries(credor.pagamento.map((politica) => [politica.campo, politica.valor]))
      gravar(this, "alterar", `/configuracao/politicas-de-pagamento?tenant_id=${credor.id}`, { tenant_setting: valores })
    },

    salvarAcordos(evento) {
      const credor = this.credor(evento)
      const politicas = Object.fromEntries(credor.acordos.map((politica) => [politica.chave, politica.escolha ? politica.valor : { kind: politica.tipo, value: politica.quantia }]))
      gravar(this, "alterar", `/configuracao/politicas-de-acordo?tenant_id=${credor.id}`, { tab: "payments", policies: politicas })
    }
  })
})
