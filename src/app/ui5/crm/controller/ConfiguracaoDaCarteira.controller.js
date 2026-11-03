// Configuração da carteira (R18, R20; 05, R104; 06, R117): o JSON da mesma rota; cada bloco de cada credor grava pela rota de sempre, com a seção.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "crm/servico/http", "crm/servico/gravar"], (Controller, JSONModel, http, gravar) => {
  "use strict"

  // A lista de opções de cada política e o campo do credor que guarda a escolha.
  const CAMPOS = { divergencias: "divergencia", correcoes: "correcao", opcoes_a_vencer: "a_vencer" }

  return Controller.extend("crm.controller.ConfiguracaoDaCarteira", {
    onInit() {
      this.getView().setModel(new JSONModel({ credores: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      this.getView().getModel("dados").setData(await http.obter("/configuracao/carteira.json"))
    },

    credor(evento) {
      const caminho = evento.getSource().getBindingContext("dados").getPath().match(/^\/credores\/\d+/)[0]
      return this.getView().getModel("dados").getProperty(caminho)
    },

    // Marcar uma opção: guarda a escolha no credor (o caminho da opção é /credores/N/<lista>/M).
    escolher(evento) {
      if (!evento.getParameter("selected")) return
      const contexto = evento.getSource().getBindingContext("dados")
      const [, credor, lista] = contexto.getPath().match(/^(\/credores\/\d+)\/(\w+)\/\d+$/)
      this.getView().getModel("dados").setProperty(`${credor}/${CAMPOS[lista]}`, contexto.getProperty("id"))
    },

    enviar(evento, secao, valores) {
      const credor = this.credor(evento)
      gravar(this, "alterar", "/configuracao/carteira", { tenant_id: credor.id, section: secao, ...valores(credor) })
    },

    salvarFaixas(evento) {
      this.enviar(evento, "brackets", (credor) => ({ brackets: credor.faixas.map((faixa) => ({ from: faixa.de, to: faixa.ate, remove: faixa.remover ? "1" : "0" })) }))
    },

    salvarDivergencia(evento) {
      this.enviar(evento, "discrepancy", (credor) => ({ discrepancy_policy: credor.divergencia }))
    },

    salvarCorrecao(evento) {
      this.enviar(evento, "correction", (credor) => ({ correction_policy: credor.correcao }))
    },

    salvarAVencer(evento) {
      this.enviar(evento, "upcoming", (credor) => ({ upcoming_display: credor.a_vencer }))
    }
  })
})
