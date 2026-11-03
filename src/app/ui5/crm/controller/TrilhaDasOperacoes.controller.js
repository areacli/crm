// Trilha das operações (14, R320, R325): a lista da mesma rota do servidor, com os filtros de sempre.
sap.ui.define(["crm/controller/Lista"], (Lista) => {
  "use strict"

  return Lista.extend("crm.controller.TrilhaDasOperacoes", {
    endereco: "/operacoes/trilha",
    filtroInicial: { operation: "", user: "", kind: "", from: "", to: "", per_page: 10, page: 1 },
    opcoesComTodos: [["filtros/operacoes", "filtro.todas"], ["filtros/usuarios", "filtro.todos"], ["filtros/tipos", "filtro.todos"]],

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    }
  })
})
