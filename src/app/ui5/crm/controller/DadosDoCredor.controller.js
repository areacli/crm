// Dados do credor (06, R106): o JSON da mesma rota; cada credor grava o cadastro e o prazo de guarda pelas rotas de sempre.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "crm/servico/http", "crm/servico/gravar"], (Controller, JSONModel, http, gravar) => {
  "use strict"

  return Controller.extend("crm.controller.DadosDoCredor", {
    onInit() {
      this.getView().setModel(new JSONModel({ credores: [], ufs: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      this.getView().getModel("dados").setData(await http.obter("/configuracao/dados-do-credor.json"))
    },

    credor(evento) {
      return evento.getSource().getBindingContext("dados").getObject()
    },

    salvarCadastro(evento) {
      const credor = this.credor(evento)
      gravar(this, "alterar", `/configuracao/dados-do-credor?tenant_id=${credor.id}`, { tenant: credor.cadastro })
    },

    salvarGuarda(evento) {
      const credor = this.credor(evento)
      gravar(this, "alterar", `/configuracao/prazo-de-guarda?tenant_id=${credor.id}`, { retention: { years: credor.anos_de_guarda } })
    }
  })
})
