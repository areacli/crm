// Ficha do credenciamento (14, R307, R310): o JSON da mesma rota; situação e vínculo em modal pequeno; desativar o vínculo pede confirmação curta.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario"],
  (Controller, JSONModel, Menu, MenuItem, MessageToast, MessageBox, http, formulario) => {
  "use strict"

  return Controller.extend("crm.controller.Operacao", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ acoes: [], pessoas: [] }), "dados")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const dados = await http.obter(`/operacoes/${this.id}.json`)
      this.getView().getModel("dados").setData(dados)
      this.aba?.setName(dados.nome)
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    mudarSituacao(evento) {
      const acao = evento.getSource().getBindingContext("dados").getObject()
      const dados = this.getView().getModel("dados").getData()
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("operacao.situacao.titulo", [acao.nome, dados.nome]), descricao: acao.descricao, perigoso: acao.perigosa,
        escopo: "accreditation", url: `/operacoes/${this.id}/situacao`, botao: acao.nome,
        campos: [{ nome: "status", tipo: "oculto", valor: acao.status }, { nome: "reason", rotulo: this.texto("distribuicao.motivo"), tipo: "texto", obrigatorio: true, max: 300 }]
      }).then((resposta) => this.concluir(resposta))
    },

    async vincular(pessoa) {
      const escolhas = await http.obter(`/operacoes/${this.id}/vinculos/novo.json?member_id=${pessoa.id}`)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("operacao.vinculo.titulo", [pessoa.nome, this.getView().getModel("dados").getProperty("/credor")]),
        escopo: "link", url: `/operacoes/${this.id}/vinculos`, botao: this.texto("operacao.vinculo.salvar"),
        campos: [{ nome: "member_id", tipo: "oculto", valor: pessoa.id }, { nome: "profile_id", rotulo: this.texto("operacao.perfil"), tipo: "opcoes", opcoes: escolhas.perfis, valor: pessoa.perfil_id }]
      }).then((resposta) => this.concluir(resposta))
    },

    desvincular(pessoa) {
      const acao = this.texto("operacao.desativarVinculo")
      MessageBox.warning(this.texto("operacao.desativarVinculo.ajuda", [this.getView().getModel("dados").getProperty("/credor")]), {
        title: this.texto("operacao.desativarVinculo.pergunta", [pessoa.nome]), actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
        onClose: async (escolha) => {
          if (escolha !== acao) return
          try {
            this.concluir(await http.excluir(`/operacoes/${this.id}/vinculos/${pessoa.vinculo_id}`))
          } catch (erro) {
            MessageBox.error(erro.corpo?.mensagem || erro.message)
          }
        }
      })
    },

    acoes(evento) {
      const pessoa = evento.getSource().getBindingContext("dados").getObject()
      const itens = [new MenuItem({ text: this.texto(pessoa.vinculo_id ? "operacao.editarPerfil" : "operacao.criarVinculo"), press: () => this.vincular(pessoa) })]
      if (pessoa.vinculo_id) itens.push(new MenuItem({ text: this.texto("operacao.desativarVinculo"), press: () => this.desvincular(pessoa) }))
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
