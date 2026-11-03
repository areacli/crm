// Lista de clientes (R21): a mesma consulta da página do servidor, em JSON; a linha abre a ficha numa aba.
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem"], (Lista, Menu, MenuItem) => {
  "use strict"

  return Lista.extend("crm.controller.Clientes", {
    endereco: "/clientes",
    filtroInicial: { q: "", tenant: "", bracket: "", segment: "", promise: "", unrecognized_city: "", sort: "overdue_cents", dir: "desc", per_page: 20, page: 1 },
    opcoesComTodos: [["filtros/credores", "filtro.todos"], ["filtros/faixas", "filtro.todas"], ["filtros/segmentos", "filtro.todos"]],

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).id) })
    },

    abrirAcoes(evento) {
      const cliente = this.objetoDaLinha(evento)
      const i18n = this.getOwnerComponent().getModel("i18n").getResourceBundle()
      const itens = [new MenuItem({ text: i18n.getText("clientes.abrirFicha"), press: () => this.navegar("cliente", { id: String(cliente.id) }) })]
      if (cliente.pode.registrar_acionamento) {
        itens.push(new MenuItem({ text: i18n.getText("ficha.registrarAcionamento"), press: () => this.navegar("cliente", { id: String(cliente.id), "?acao": { painel: "acionamento" } }) }))
      }
      const menu = new Menu({ items: itens, closed: () => setTimeout(() => menu.destroy()) })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    },

    // Até a distribuição ser portada (fase G), o lote "destes clientes" abre a página do servidor com o mesmo filtro (14, R316).
    distribuir() {
      window.location.assign(`/distribuicao/lotes/novo?${this.consulta()}`)
    }
  })
})
