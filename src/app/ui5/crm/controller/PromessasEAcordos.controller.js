// Promessas e acordos (10, R189, R190, R206; 11, R207, R209, R243): o JSON da mesma rota; cada cartão de cada credor grava pela rota de sempre. As
// variáveis de acordo devolvem o endereço da conferência do impacto do enquadramento (13, R272), que abre numa aba.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/MessageBox", "crm/servico/http", "crm/servico/gravar"],
  (Controller, JSONModel, formatMessage, MessageBox, http, gravar) => {
  "use strict"

  // Põe `valor` em `objeto` pela chave com ponto ("caps.cash.interest" vira { caps: { cash: { interest: valor } } }).
  function definir(objeto, chave, valor) {
    const partes = chave.split(".")
    const ultima = partes.pop()
    partes.reduce((atual, parte) => (atual[parte] ||= {}), objeto)[ultima] = valor
    return objeto
  }

  // Os campos de um bloco (item ou perfil em item) no formato do envio, com o segundo campo da linha (o teto à vista).
  function linha(campos) {
    return campos.reduce((objeto, campo) => {
      definir(objeto, campo.chave, campo.valor)
      if (campo.par) definir(objeto, campo.par.chave, campo.par.valor)
      return objeto
    }, {})
  }

  return Controller.extend("crm.controller.PromessasEAcordos", {
    formatarTexto: formatMessage,

    onInit() {
      this.getView().setModel(new JSONModel({ credores: [] }), "dados")
      this.carregar()
    },

    async carregar() {
      const view = this.getView()
      view.setBusy(true)
      try {
        view.getModel("dados").setData(await http.obter("/configuracao/promessas-e-acordos.json"))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      } finally {
        view.setBusy(false)
      }
    },

    // O credor do cartão do botão (o contexto do botão é /credores/N).
    credor(evento) {
      return evento.getSource().getBindingContext("dados").getObject()
    },

    salvarPoliticasDaPromessa(evento) {
      const credor = this.credor(evento)
      const promessa = credor.promessa
      gravar(this, "alterar", "/configuracao/politicas-de-promessa", { tenant_id: credor.id, tenant_setting: {
        promise_tolerance_days: promessa.tolerancia, promise_grace_days: promessa.carencia, promise_min_paid_pct: promessa.minimo,
        promise_counting: promessa.contam, promise_after_break: promessa.depois_da_quebra, promise_partial: promessa.parcial
      } })
    },

    salvarAlcadas(evento) {
      const credor = this.credor(evento)
      const tiers = Object.fromEntries(credor.alcadas.map((item) => [item.id, linha(item.campos)]))
      gravar(this, "alterar", "/configuracao/alcada-de-promessa", { tenant_id: credor.id, tiers })
    },

    salvarPoliticasDosAcordos(evento) {
      const credor = this.credor(evento)
      const policies = Object.fromEntries(credor.politicas_de_acordo.map((politica) =>
        [politica.chave, politica.de_escolha ? politica.escolha : { kind: politica.escolha, value: politica.escolha === "tolerance" ? "" : politica.quantia }]))
      gravar(this, "alterar", "/configuracao/politicas-de-acordo", { tenant_id: credor.id, tab: "agreements", policies })
    },

    salvarLimites(evento) {
      const credor = this.credor(evento)
      const limits = {}
      credor.limites.forEach((bloco) => { (limits[bloco.item_id] ||= {})[bloco.perfil_id] = linha(bloco.campos) })
      gravar(this, "alterar", "/configuracao/limites-de-acordo", { tenant_id: credor.id, limits })
    },

    // As variáveis não valem na hora: o servidor guarda a proposta e devolve o endereço da conferência (/configuracao/conferencias-do-enquadramento/:id),
    // que abre na aba da SPA. A recusa volta como mensagem, sem sair da tela.
    async conferirVariaveis(evento) {
      const credor = this.credor(evento)
      const tiers = Object.fromEntries(credor.variaveis.map((item) => [item.id, linha(item.campos)]))
      try {
        const resposta = await http.alterar("/configuracao/variaveis-de-acordo", { tenant_id: credor.id, tiers })
        const endereco = new URL(resposta.destino, window.location.origin)
        const id = endereco.pathname.match(/\/conferencias-do-enquadramento\/([^/]+)$/)?.[1]
        if (!id) return this.carregar()
        this.getOwnerComponent().getRouter().navTo("conferenciaDoEnquadramento", { id })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
        this.carregar()
      }
    }
  })
})
