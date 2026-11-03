// Lista de acordos (11, R243): a mesma consulta da página do servidor, em JSON. O número abre o acordo numa aba; o cliente, a ficha. Tempo
// real: a lista se refaz quando um acordo muda (recurso `clientes`, publicado pelo acordo).
sap.ui.define(["crm/controller/Lista", "crm/servico/telas", "crm/servico/tempo-real"], (Lista, telas, tempoReal) => {
  "use strict"

  return Lista.extend("crm.controller.Acordos", {
    endereco: "/acordos",
    filtroInicial: { state: "", from: "", to: "", user: "", origin: "", tenant: "", per_page: 10, page: 1 },
    opcoesComTodos: [["filtros/situacoes", "filtro.todas"], ["filtros/operadores", "filtro.todos"], ["filtros/origens", "filtro.todas"], ["filtros/credores", "filtro.todos"]],

    onInit() {
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("clientes", () => this.carregar()), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    abrirAcordo(evento) {
      const linha = this.objetoDaLinha(evento)
      this.navegar("acordo", { id: String(linha.acordo_id || linha.id) })
    },

    abrirFicha(evento) {
      this.navegar("cliente", { id: String(this.objetoDaLinha(evento).cliente_id) })
    },

    // O detalhe de um caso do gestor leva a uma tela (a da SPA, se já existe; senão, a do servidor).
    abrirEndereco(evento) {
      const endereco = this.objetoDaLinha(evento).endereco
      const destino = telas.doCaminho(endereco.split("?")[0])
      if (destino) return this.navegar(destino.tela.rota, destino.argumentos)
      window.location.assign(endereco)
    },

    abrirArquivo() {
      const destino = telas.doCaminho("/arquivo-de-acordos")
      if (destino) return this.navegar(destino.tela.rota, destino.argumentos)
      window.location.assign("/arquivo-de-acordos")
    }
  })
})
