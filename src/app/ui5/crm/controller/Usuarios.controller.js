// Usuários (R36, R40): a lista da mesma rota; o novo usuário no painel lateral, com o perfil do credor escolhido; as ações do vínculo pelo serviço
// compartilhado com a ficha do usuário.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "crm/servico/http", "crm/servico/formulario",
  "crm/servico/painel", "crm/servico/senha-temporaria", "crm/servico/acoes-do-usuario"],
  (Lista, JSONModel, Menu, MenuItem, MessageToast, http, formulario, painel, senhaTemporaria, acoesDoUsuario) => {
  "use strict"

  return Lista.extend("crm.controller.Usuarios", {
    endereco: "/usuarios",
    filtroInicial: { q: "", tenant: "", per_page: 20, page: 1 },
    opcoesComTodos: [["credores", "filtro.todos"]],

    onInit() {
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      this.acoesDoUsuario = acoesDoUsuario(this)
      Lista.prototype.onInit.apply(this, arguments)
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    abrir(evento) {
      this.navegar("usuario", { id: String(this.objetoDaLinha(evento).id) })
    },

    async novo() {
      const { credores } = await http.obter("/usuarios/novo.json")
      const perfis = Object.fromEntries(credores.map((credor) => [credor.id, credor.perfis]))
      const campoDoCredor = credores.length > 1
        ? { nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: credores, valor: credores[0].id }
        : { nome: "tenant_id", tipo: "oculto", valor: credores[0]?.id }
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("usuarios.novo"), descricao: this.texto("usuarios.novo.ajuda"),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "membership", url: "/usuarios", botao: this.texto("acao.salvar"),
        campos: [
          campoDoCredor,
          { nome: "email_address", rotulo: this.texto("operacao.email"), tipo: "texto", obrigatorio: true, max: 200, ajuda: this.texto("usuarios.email.ajuda") },
          { nome: "name", rotulo: this.texto("enquadramento.nome"), tipo: "texto", max: 150, ajuda: this.texto("usuarios.nome.ajuda") },
          { nome: "profile_id", rotulo: this.texto("operacao.perfil"), tipo: "opcoes", opcoes: perfis[credores[0]?.id] || [], dependeDe: "tenant_id", opcoesPor: perfis }
        ]
      }).then((resposta) => {
        if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
        senhaTemporaria(this, resposta)
        this.carregar()
      })
    },

    acoes(evento) {
      const linha = this.objetoDaLinha(evento)
      const credor = linha.credor
      const itens = [new MenuItem({ text: this.texto("usuarios.abrir"), press: () => this.navegar("usuario", { id: String(linha.id) }) })]
      if (!linha.proprio) {
        itens.push(new MenuItem({ text: this.texto("usuarios.editarPerfil"), press: () => this.acoesDoUsuario.editarPerfil(linha.id) }))
        itens.push(linha.ativo
          ? new MenuItem({ text: this.texto("usuarios.desativar"), press: () => this.acoesDoUsuario.desativar(linha.id, linha.nome_da_pessoa, credor) })
          : new MenuItem({ text: this.texto("usuarios.reativar"), press: () => this.acoesDoUsuario.reativar(linha.id, linha.nome_da_pessoa, credor) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
