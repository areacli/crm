// Perfis (R30 a R35): a lista da mesma rota; criar e editar no painel lateral, com as permissões marcadas numa lista; excluir com confirmação curta.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http",
  "crm/servico/formulario", "crm/servico/painel"],
  (Lista, JSONModel, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel) => {
  "use strict"

  return Lista.extend("crm.controller.Perfis", {
    endereco: "/perfis",
    filtroInicial: { tenant: "", per_page: 20, page: 1 },
    opcoesComTodos: [["credores", "filtro.todos"]],

    onInit() {
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      Lista.prototype.onInit.apply(this, arguments)
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    formularioDoPerfil(perfil, titulo, url, metodo) {
      const campoDoCredor = perfil.credores.length > 1
        ? { nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: perfil.credores, valor: perfil.credor_id }
        : { nome: "tenant_id", tipo: "oculto", valor: perfil.credor_id }
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo, descricao: perfil.credores.length > 1 ? null : this.texto("perfis.credor", [perfil.credor]),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "profile", url, metodo, botao: this.texto("perfis.salvar"),
        campos: [
          ...(metodo === "POST" ? [campoDoCredor] : []),
          { nome: "name", rotulo: this.texto("perfis.nome"), tipo: "texto", obrigatorio: true, max: 100, valor: perfil.nome },
          { nome: "available_to_operations", rotulo: this.texto("perfis.deOperacao"), tipo: "marca", valor: perfil.de_operacao, ajuda: this.texto("perfis.deOperacao.ajuda") },
          { nome: "permissions", rotulo: this.texto("perfis.permissoes"), tipo: "marcas", opcoes: perfil.permissoes, valor: perfil.marcadas, ajuda: this.texto("perfis.permissoes.ajuda") }
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    async criar() {
      this.formularioDoPerfil(await http.obter("/perfis/novo.json"), this.texto("perfis.criar"), "/perfis", "POST")
    },

    async editar(linha) {
      this.formularioDoPerfil(await http.obter(`/perfis/${linha.id}/editar.json`), this.texto("perfis.editar", [linha.nome]), `/perfis/${linha.id}`, "PATCH")
    },

    editarDaLinha(evento) {
      this.editar(this.objetoDaLinha(evento))
    },

    excluir(linha) {
      const acao = this.texto("perfis.excluir")
      MessageBox.warning(linha.mensagem_de_excluir, {
        title: this.texto("perfis.excluir.pergunta", [linha.nome]), actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
        onClose: async (escolha) => {
          if (escolha !== acao) return
          try { this.concluir(await http.excluir(`/perfis/${linha.id}`)) } catch (erro) { MessageBox.error(erro.corpo?.mensagem || erro.message) }
        }
      })
    },

    acoes(evento) {
      const linha = this.objetoDaLinha(evento)
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("acao.editar"), press: () => this.editar(linha) }),
        new MenuItem({ text: this.texto("acao.excluir"), press: () => this.excluir(linha) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
