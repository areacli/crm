// Página da integração (12, R259 a R269): o JSON da mesma rota; salvar vai como formulário (o certificado é arquivo) à rota de sempre; testar, ativar,
// desativar, gerar segredo e excluir pelas rotas de sempre, com confirmação curta onde a página pedia.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/confirmar",
  "crm/servico/mostrar-segredo", "crm/servico/campos-da-integracao"],
  (Controller, JSONModel, MessageToast, MessageBox, http, confirmar, mostrarSegredo, camposDaIntegracao) => {
  "use strict"

  return Controller.extend("crm.controller.Integracao", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ metodos: [], conexao: [], historico: [], situacao: {} }), "dados")
      this.getView().setModel(new JSONModel({ enviando: false }), "ui")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    base() {
      return `/configuracao/integracoes/${this.id}`
    },

    async carregar() {
      const dados = await http.obter(`${this.base()}/editar.json`)
      this.getView().getModel("dados").setData(dados)
      this.entradas = camposDaIntegracao.montar(this.byId("campos"), dados.campos)
      this.aba?.setName(dados.nome)
    },

    async salvar() {
      const dados = this.getView().getModel("dados").getData()
      const formulario = new FormData()
      formulario.append("_method", "patch")
      formulario.append("payment_account[nickname]", dados.apelido)
      formulario.append("payment_account[channel_id]", dados.metodo_id)
      camposDaIntegracao.preencher(formulario, this.entradas)
      const ui = this.getView().getModel("ui")
      ui.setProperty("/enviando", true)
      try {
        const resposta = await http.enviarFormulario(this.base(), formulario)
        MessageToast.show(resposta.mensagem || "", { duration: 6000 })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      } finally {
        ui.setProperty("/enviando", false)
        this.carregar()
      }
    },

    async executar(metodo, caminho) {
      try {
        const resposta = await http[metodo](`${this.base()}/${caminho}`, metodo === "excluir" ? undefined : {})
        MessageToast.show(resposta?.mensagem || "", { duration: 6000 })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
      this.carregar()
    },

    testar() {
      this.executar("enviar", "teste-de-conexao")
    },

    ativar() {
      this.executar("enviar", "ativacao")
    },

    desativar() {
      confirmar({ titulo: this.texto("integracao.desativar.pergunta"), mensagem: this.texto("integracao.desativar.ajuda"), acao: this.texto("integracao.desativar"),
        executar: () => http.excluir(`${this.base()}/ativacao`) }).then(() => this.carregar())
    },

    gerarSegredo() {
      confirmar({ titulo: this.texto("metodos.gerarSegredo.pergunta"), mensagem: this.texto("integracao.gerarSegredo.ajuda"), acao: this.texto("metodos.gerarSegredo"), perigosa: false,
        executar: () => http.enviar(`${this.base()}/segredo-do-webhook`, {}) }).then((resposta) => { mostrarSegredo(this, resposta); this.carregar() })
    },

    excluir() {
      const apelido = this.getView().getModel("dados").getProperty("/apelido")
      confirmar({ titulo: this.texto("integracao.excluir.pergunta"), mensagem: this.texto("integracao.excluir.ajuda", [apelido]), acao: this.texto("integracao.excluir"),
        executar: () => http.excluir(this.base()) }).then((resposta) => { if (resposta) this.getOwnerComponent().getRouter().navTo("metodosDeRecebimento", {}) })
    }
  })
})
