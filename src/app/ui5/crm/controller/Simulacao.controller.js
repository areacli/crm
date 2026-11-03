// Simular acordo (11, R211 a R218): o formulário do Rails em JSON; a cada mudança, a simulação (nada é gravado); "Criar proposta" grava pela rota
// de sempre e abre o acordo numa aba. A recusa marca o campo que o servidor apontou.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "crm/servico/http"], (Controller, JSONModel, MessageToast, http) => {
  "use strict"

  return Controller.extend("crm.controller.Simulacao", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.getView().setModel(new JSONModel({ titulos: [], componentes: [] }), "form")
      this.getView().setModel(new JSONModel({ mode: "installments", down_payment: "", down_payment_on: "", installments: "", day: "", credit: "", replace: false }), "valores")
      this.getView().setModel(new JSONModel({}), "resultado")
      this.getView().setModel(new JSONModel({ campo: null, problema: null, erroDaProposta: null }), "ui")
      this.carregar()
    },

    async carregar() {
      const form = await http.obter(`/clientes/${this.id}/simulacao-de-acordo/new.json`)
      form.titulos.forEach((titulo) => { titulo.escolhido = false })
      form.componentes.forEach((componente) => { componente.valor = "" })
      this.getView().getModel("form").setData(form)
      this.aba?.setName(`${this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("simulacao.titulo")} · ${form.cliente}`)
    },

    // Os parâmetros do formulário de acordo, no formato da página do servidor.
    parametros() {
      const valores = this.getView().getModel("valores").getData()
      const form = this.getView().getModel("form").getData()
      return {
        mode: valores.mode, down_payment: valores.down_payment, down_payment_on: valores.down_payment_on, installments: valores.installments, day: valores.day,
        credit: valores.credit, replace: valores.replace ? "1" : "0",
        bill_ids: form.titulos.filter((titulo) => titulo.escolhido).map((titulo) => titulo.id),
        discounts: Object.fromEntries(form.componentes.filter((componente) => componente.valor !== "").map((componente) => [componente.id, componente.valor]))
      }
    },

    mudarForma(evento) {
      this.getView().getModel("valores").setProperty("/mode", evento.getParameter("selectedIndex") === 1 ? "cash" : "installments")
      this.simularDepois()
    },

    simularDepois() {
      clearTimeout(this.espera)
      this.espera = setTimeout(() => this.simular(), 400)
    },

    async simular() {
      const resultado = await http.enviar(`/clientes/${this.id}/simulacao-de-acordo.json`, { agreement: this.parametros() })
      this.getView().getModel("resultado").setData(resultado)
      this.getView().getModel("ui").setData({ campo: resultado.campo, problema: resultado.problema, erroDaProposta: null })
    },

    async criarProposta() {
      const botao = this.byId("criarProposta")
      botao.setBusy(true)
      try {
        const resposta = await http.enviar(`/clientes/${this.id}/acordos`, { agreement: this.parametros() })
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        const numero = resposta.destino?.match(/\/acordos\/(\d+)/)?.[1]
        if (numero) this.getOwnerComponent().getRouter().navTo("acordo", { id: numero })
      } catch (erro) {
        this.getView().getModel("ui").setData({ campo: erro.corpo?.campo, problema: erro.corpo?.mensagem, erroDaProposta: erro.corpo?.mensagem || erro.message })
      } finally {
        botao.setBusy(false)
      }
    },

    abrirFicha() {
      this.getOwnerComponent().getRouter().navTo("cliente", { id: String(this.id) })
    }
  })
})
