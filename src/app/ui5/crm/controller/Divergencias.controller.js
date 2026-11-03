// Divergências de valor (05, R99): a lista em JSON; tratar pede a nota e a escolha num modal pequeno (o mesmo da página da divergência).
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem", "crm/servico/tratar-divergencia"], (Lista, Menu, MenuItem, tratarDivergencia) => {
  "use strict"

  return Lista.extend("crm.controller.Divergencias", {
    endereco: "/divergencias-de-valor",
    filtroInicial: { status: "open", tenant: "", per_page: 10, page: 1 },
    opcoesComTodos: [["credores", "filtro.todos"]],

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    abrir(evento) {
      this.navegar("divergencia", { id: String(this.objetoDaLinha(evento).id) })
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    acoes(evento) {
      const item = this.objetoDaLinha(evento)
      const itens = [new MenuItem({ text: this.texto("divergencias.abrir"), press: () => this.navegar("divergencia", { id: String(item.id) }) })]
      if (item.pode_tratar) itens.push(new MenuItem({ text: this.texto("divergencias.tratar"), press: () => tratarDivergencia(this, item.id).then(() => this.carregar()) }))
      if (item.titulo_endereco) itens.push(new MenuItem({ text: this.texto("divergencias.historicoDoTitulo"), press: () => this.abrirTitulo(item.titulo_endereco) }))
      const menu = new Menu({ items: itens, closed: () => setTimeout(() => menu.destroy()) })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    },

    abrirTitulo(endereco) {
      this.navegar("titulo", { id: endereco.split("/").pop() })
    }
  })
})
