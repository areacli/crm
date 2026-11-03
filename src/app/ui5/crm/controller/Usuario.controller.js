// Ficha do usuário (R36 a R42): o JSON da mesma rota; as ações do vínculo pelo serviço compartilhado com a lista.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Menu", "sap/m/MenuItem", "crm/servico/http", "crm/servico/acoes-do-usuario"],
  (Controller, JSONModel, formatMessage, Menu, MenuItem, http, acoesDoUsuario) => {
  "use strict"

  return Controller.extend("crm.controller.Usuario", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.acoesDoUsuario = acoesDoUsuario(this)
      this.getView().setModel(new JSONModel({ acesso: [], historico: [], situacao: {} }), "dados")
      this.carregar()
    },

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    async carregar() {
      const dados = await http.obter(`/usuarios/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(dados.nome)
    },

    dados() {
      return this.getView().getModel("dados").getData()
    },

    editarPerfil() {
      this.acoesDoUsuario.editarPerfil(this.id)
    },

    desativar() {
      this.acoesDoUsuario.desativar(this.id, this.dados().nome, this.dados().credor)
    },

    reativar() {
      this.acoesDoUsuario.reativar(this.id, this.dados().nome, this.dados().credor)
    },

    maisAcoes(evento) {
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("usuarios.editarNome"), press: () => this.acoesDoUsuario.editarNome(this.id) }),
        new MenuItem({ text: this.texto("usuarios.redefinirSenha"), press: () => this.acoesDoUsuario.redefinirSenha(this.id, this.dados().nome) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
