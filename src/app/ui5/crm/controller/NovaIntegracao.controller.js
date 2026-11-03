// Nova integração (12, R259): "Continuar" pede ao servidor os campos do manifesto do fornecedor e do meio escolhidos; "Salvar" envia o formulário (com o
// certificado) à rota de sempre e abre a página da integração criada.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/campos-da-integracao"],
  (Controller, JSONModel, MessageToast, MessageBox, http, camposDaIntegracao) => {
  "use strict"

  return Controller.extend("crm.controller.NovaIntegracao", {
    onInit() {
      this.getView().setModel(new JSONModel({ credores: [], meios: [], fornecedores: [], escolha: {}, metodos: [], ambientes: [] }), "dados")
      this.getView().setModel(new JSONModel({ apelido: "", ambiente: "sandbox", metodo: "", enviando: false }), "ui")
      this.carregar("")
    },

    async carregar(consulta) {
      let dados
      try {
        dados = await http.obter(`/configuracao/integracoes/nova.json${consulta}`)
      } catch (erro) {
        return MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
      this.getView().getModel("dados").setData(dados)
      this.getView().getModel("ui").setProperty("/metodo", dados.metodos[0]?.id || "")
      this.entradas = dados.escolhida ? camposDaIntegracao.montar(this.byId("campos"), dados.campos) : []
    },

    continuar() {
      const { credor, meio, fornecedor } = this.getView().getModel("dados").getProperty("/escolha")
      this.carregar(`?tenant_id=${encodeURIComponent(credor)}&modality=${encodeURIComponent(meio)}&provider=${encodeURIComponent(fornecedor)}`)
    },

    async salvar() {
      const escolha = this.getView().getModel("dados").getProperty("/escolha")
      const ui = this.getView().getModel("ui")
      const formulario = new FormData()
      formulario.append("payment_account[tenant_id]", escolha.credor)
      formulario.append("payment_account[modality]", escolha.meio)
      formulario.append("payment_account[provider]", escolha.fornecedor)
      formulario.append("payment_account[nickname]", ui.getProperty("/apelido"))
      formulario.append("payment_account[environment]", ui.getProperty("/ambiente"))
      formulario.append("payment_account[channel_id]", ui.getProperty("/metodo"))
      camposDaIntegracao.preencher(formulario, this.entradas)
      ui.setProperty("/enviando", true)
      try {
        const resposta = await http.enviarFormulario("/configuracao/integracoes", formulario)
        MessageToast.show(resposta.mensagem || "", { duration: 6000 })
        this.getOwnerComponent().getRouter().navTo("integracao", { id: resposta.destino.split("/").at(-2) })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      } finally {
        ui.setProperty("/enviando", false)
      }
    }
  })
})
