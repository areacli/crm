// Envio de arquivo (R10, R56): o arquivo vai como formulário (multipart) à rota de sempre; a recusa (422) volta na tela; o aceite abre a página da
// importação numa aba, onde a conferência corre ao vivo.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/MessageToast", "sap/m/library", "crm/servico/http"],
  (Controller, JSONModel, formatMessage, MessageToast, mobileLibrary, http) => {
  "use strict"

  return Controller.extend("crm.controller.NovaImportacao", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.tipo = argumentos.tipo || "portfolio"
      this.aba = aba
      this.getView().setModel(new JSONModel({ credores: [], colunas: [] }), "dados")
      this.getView().setModel(new JSONModel({ credor: "", modo: 0, temArquivo: false, enviando: false, erro: "" }), "ui")
      this.carregar()
    },

    async carregar() {
      const dados = await http.obter(`/importacoes/nova.json?kind=${encodeURIComponent(this.tipo)}`)
      this.getView().getModel("dados").setData(dados)
      this.getView().getModel("ui").setProperty("/credor", dados.credores[0]?.id || "")
      this.aba?.setName(dados.titulo)
    },

    escolherArquivo(evento) {
      this.arquivo = evento.getParameter("files")?.[0]
      this.getView().getModel("ui").setProperty("/temArquivo", Boolean(this.arquivo))
    },

    baixarModelo() {
      mobileLibrary.URLHelper.redirect(this.getView().getModel("dados").getProperty("/modelo"))
    },

    async enviar() {
      const ui = this.getView().getModel("ui")
      const formulario = new FormData()
      formulario.append("import[kind]", this.tipo)
      formulario.append("import[tenant_id]", ui.getProperty("/credor"))
      formulario.append("import[mode]", ui.getProperty("/modo") === 1 ? "full_sync" : "incremental")
      formulario.append("import[file]", this.arquivo)
      ui.setProperty("/enviando", true)
      ui.setProperty("/erro", "")
      try {
        const resposta = await http.enviarFormulario("/importacoes", formulario)
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.getOwnerComponent().getRouter().navTo("importacao", { id: resposta.destino.split("/").pop() })
      } catch (erro) {
        ui.setProperty("/erro", erro.corpo?.mensagem || erro.message)
      } finally {
        ui.setProperty("/enviando", false)
      }
    }
  })
})
