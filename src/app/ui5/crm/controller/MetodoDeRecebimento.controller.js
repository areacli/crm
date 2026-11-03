// Página do método de recebimento (16, R373; R45): o JSON da mesma rota; salvar pela rota de sempre; gerar segredo e excluir com confirmação curta.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "crm/servico/http", "crm/servico/gravar", "crm/servico/confirmar", "crm/servico/mostrar-segredo"],
  (Controller, JSONModel, http, gravar, confirmar, mostrarSegredo) => {
  "use strict"

  return Controller.extend("crm.controller.MetodoDeRecebimento", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ tipos: [], webhook: {} }), "dados")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const dados = await http.obter(`/configuracao/metodos-de-recebimento/${this.id}/editar.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(dados.nome)
    },

    salvar() {
      const dados = this.getView().getModel("dados").getData()
      gravar(this, "alterar", `/configuracao/metodos-de-recebimento/${this.id}`, { payment_channel: { kind: dados.tipo, code: dados.codigo, description: dados.descricao, active: dados.ativo ? "1" : "0" } })
    },

    gerarSegredo() {
      confirmar({ titulo: this.texto("metodos.gerarSegredo.pergunta"), mensagem: this.texto("metodos.gerarSegredo.ajuda"), acao: this.texto("metodos.gerarSegredo"), perigosa: false,
        executar: () => http.enviar(`/configuracao/metodos-de-recebimento/${this.id}/segredo-do-webhook`, {}) })
        .then((resposta) => { mostrarSegredo(this, resposta); this.carregar() })
    },

    excluir() {
      const codigo = this.getView().getModel("dados").getProperty("/codigo")
      confirmar({ titulo: this.texto("metodos.excluir.pergunta"), mensagem: this.texto("metodos.excluir.ajuda", [codigo]), acao: this.texto("metodos.excluir"),
        executar: () => http.excluir(`/configuracao/metodos-de-recebimento/${this.id}`) })
        .then((resposta) => { if (resposta) this.getOwnerComponent().getRouter().navTo("metodosDeRecebimento", {}) })
    }
  })
})
