// Distribuir em lote (14, R316): o formulário vai como multipart (a planilha) à rota de sempre; a recusa (422) volta na tela; o aceite abre a
// página do lote numa aba. Vindo da lista de clientes, o filtro dela chega pelo endereço e vira a primeira origem.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "crm/servico/http"], (Controller, JSONModel, http) => {
  "use strict"

  const TIPOS = ["selection", "segment", "file"]

  return Controller.extend("crm.controller.NovoLote", {
    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.selecao = argumentos["?filtro"] || null
      this.aba = aba
      const comSelecao = Boolean(this.selecao && Object.keys(this.selecao).length)
      this.getView().setModel(new JSONModel({ credenciadas: [], segmentos: [], exposicoes: [] }), "dados")
      this.getView().setModel(new JSONModel({ comSelecao, origem: comSelecao ? 0 : 1, tipo: comSelecao ? "selection" : "segment", operacao: "", segmento: "",
        exposicao: "", inicio: new Date().toISOString().slice(0, 10), fim: "", erro: "", enviando: false }), "ui")
      this.carregar()
    },

    async carregar() {
      const dados = await http.obter("/distribuicao/lotes/novo.json")
      this.getView().getModel("dados").setData(dados)
      const ui = this.getView().getModel("ui")
      ui.setProperty("/operacao", dados.credenciadas[0]?.id || "")
      ui.setProperty("/exposicao", dados.exposicoes[0]?.id || "")
    },

    mudarOrigem(evento) {
      this.getView().getModel("ui").setProperty("/tipo", TIPOS[evento.getParameter("selectedIndex")])
    },

    escolherArquivo(evento) {
      this.arquivo = evento.getParameter("files")?.[0]
    },

    async conferir() {
      const ui = this.getView().getModel("ui")
      const formulario = new FormData()
      const tipo = ui.getProperty("/tipo")
      formulario.append("distribution_batch[accreditation_id]", ui.getProperty("/operacao"))
      formulario.append("distribution_batch[kind]", tipo)
      formulario.append("distribution_batch[segment_id]", tipo === "segment" ? ui.getProperty("/segmento") : "")
      if (tipo === "file" && this.arquivo) formulario.append("distribution_batch[file]", this.arquivo)
      if (tipo === "selection") Object.entries(this.selecao).forEach(([chave, valor]) => formulario.append(`distribution_batch[selection][${chave}]`, valor))
      formulario.append("distribution_batch[exposure]", ui.getProperty("/exposicao"))
      formulario.append("distribution_batch[starts_on]", ui.getProperty("/inicio") || "")
      formulario.append("distribution_batch[ends_on]", ui.getProperty("/fim") || "")
      ui.setProperty("/enviando", true)
      ui.setProperty("/erro", "")
      try {
        const resposta = await http.enviarFormulario("/distribuicao/lotes", formulario)
        this.getOwnerComponent().getRouter().navTo("lote", { id: resposta.destino.split("/").pop() })
      } catch (erro) {
        ui.setProperty("/erro", erro.corpo?.mensagem || erro.message)
      } finally {
        ui.setProperty("/enviando", false)
      }
    }
  })
})
