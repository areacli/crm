// Importações (R10, R56): a lista da mesma rota do servidor. Tempo real: a situação de cada importação chega pelo recurso `importacoes`;
// uma importação nova (de outra pessoa) refaz a página.
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem", "crm/servico/tempo-real", "crm/servico/confirmar-importacao"],
  (Lista, Menu, MenuItem, tempoReal, confirmarImportacao) => {
  "use strict"

  return Lista.extend("crm.controller.Importacoes", {
    endereco: "/importacoes",
    filtroInicial: { per_page: 10, page: 1 },

    onInit() {
      Lista.prototype.onInit.apply(this, arguments)
      this.desligar = [tempoReal.ouvir("importacoes", (mensagem) => this.atualizar(mensagem)), tempoReal.ouvir("*conectado", () => this.carregar())]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // Troca a situação das linhas que mudaram; uma importação que não está na página (nova) refaz a lista.
    atualizar(mensagem) {
      if (mensagem.acao !== "atualizar") return this.carregar()
      const dados = this.getView().getModel("dados")
      const linhas = dados.getProperty("/linhas")
      let nova = false
      mensagem.registros.forEach((registro) => {
        const indice = linhas.findIndex((linha) => linha.id === registro.id)
        if (indice < 0) nova = true
        else Object.assign(linhas[indice], registro)
      })
      if (nova || mensagem.removidos?.length) return this.carregar()
      dados.refresh(true)
    },

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    importar(evento) {
      this.navegar("novaImportacao", { tipo: evento.getSource().data("tipo") })
    },

    abrir(evento) {
      this.navegar("importacao", { id: String(this.objetoDaLinha(evento).id) })
    },

    acoes(evento) {
      const importacao = this.objetoDaLinha(evento)
      const itens = [new MenuItem({ text: this.texto("importacao.abrir"), press: () => this.navegar("importacao", { id: String(importacao.id) }) })]
      if (importacao.pode_confirmar) {
        itens.push(new MenuItem({ text: this.texto("importacao.confirmar"), press: () => confirmarImportacao(this, importacao, "confirmar").then(() => this.carregar()) }))
        itens.push(new MenuItem({ text: this.texto("importacao.descartar"), press: () => confirmarImportacao(this, importacao, "descartar").then(() => this.carregar()) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
