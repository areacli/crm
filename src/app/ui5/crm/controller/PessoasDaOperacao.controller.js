// Pessoas da operação (14, R310, R310a, R327): o JSON da mesma rota; criar no painel lateral; vínculo em modal pequeno, com o perfil do credor
// escolhido; gestor, desativar e reativar com confirmação curta.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/painel", "crm/servico/senha-temporaria"],
  (Controller, JSONModel, formatMessage, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel, senhaTemporaria) => {
  "use strict"

  return Controller.extend("crm.controller.PessoasDaOperacao", {
    formatarTexto: formatMessage,

    onInit() {
      this.getView().setModel(new JSONModel({ linhas: [] }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      this.getView().getModel("dados").setData(await http.obter("/operacao/pessoas.json"))
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      senhaTemporaria(this, resposta)
      this.carregar()
    },

    criar() {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("pessoas.nova"), descricao: this.texto("pessoas.nova.ajuda"),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "operation_member", url: "/operacao/pessoas", botao: this.texto("pessoas.criar"),
        campos: [
          { nome: "name", rotulo: this.texto("enquadramento.nome"), tipo: "texto", obrigatorio: true, max: 200 },
          { nome: "email_address", rotulo: this.texto("operacao.email"), tipo: "texto", obrigatorio: true, max: 200 },
          { nome: "manager", rotulo: this.texto("pessoas.gestor"), tipo: "marca" }
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    async vincular(pessoa) {
      const dados = await http.obter(`/operacao/pessoas/${pessoa.id}/vinculos/novo.json`)
      const perfis = Object.fromEntries(dados.credores.map((credor) => [credor.id, credor.perfis]))
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("pessoas.vinculo.titulo", [dados.nome]), descricao: this.texto("pessoas.vinculo.ajuda"),
        escopo: "link", url: `/operacao/pessoas/${pessoa.id}/vinculos`, botao: this.texto("operacao.vinculo.salvar"),
        campos: [
          { nome: "accreditation_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: dados.credores, valor: dados.credores[0]?.id },
          { nome: "profile_id", rotulo: this.texto("operacao.perfil"), tipo: "opcoes", opcoes: perfis[dados.credores[0]?.id] || [], dependeDe: "accreditation_id", opcoesPor: perfis }
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    mudar(pessoa, mudanca, titulo, mensagem, acao, perigosa) {
      MessageBox[perigosa ? "warning" : "confirm"](mensagem, {
        title: titulo, actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
        onClose: async (escolha) => {
          if (escolha !== acao) return
          try { this.concluir(await http.alterar(`/operacao/pessoas/${pessoa.id}?change=${mudanca}`, {})) } catch (erro) { MessageBox.error(erro.corpo?.mensagem || erro.message) }
        }
      })
    },

    acoes(evento) {
      const pessoa = evento.getSource().getBindingContext("dados").getObject()
      const nome = pessoa.nome_da_pessoa
      const confirmar = this.texto("pessoas.confirmar")
      const itens = []
      if (pessoa.ativa) {
        if (this.getView().getModel("dados").getProperty("/pode_vincular")) itens.push(new MenuItem({ text: this.texto("operacao.criarVinculo"), press: () => this.vincular(pessoa) }))
        itens.push(pessoa.gestor
          ? new MenuItem({ text: this.texto("pessoas.desmarcarGestor"), press: () => this.mudar(pessoa, "not_manager", this.texto("pessoas.desmarcarGestor.pergunta", [nome]), this.texto("pessoas.gestor.ajuda"), confirmar, false) })
          : new MenuItem({ text: this.texto("pessoas.marcarGestor"), press: () => this.mudar(pessoa, "manager", this.texto("pessoas.marcarGestor.pergunta", [nome]), this.texto("pessoas.gestor.ajuda"), confirmar, false) }))
        itens.push(new MenuItem({ text: this.texto("pessoas.desativar"), press: () => this.mudar(pessoa, "deactivate", this.texto("pessoas.desativar.pergunta", [nome]), this.texto("pessoas.desativar.ajuda"), this.texto("pessoas.desativar"), true) }))
      } else {
        itens.push(new MenuItem({ text: this.texto("pessoas.reativar"), press: () => this.mudar(pessoa, "activate", this.texto("pessoas.reativar.pergunta", [nome]), this.texto("pessoas.reativar.ajuda"), this.texto("pessoas.reativar"), false) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
