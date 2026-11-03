// Arquivo de acordos (11, R244): a lista em JSON; exportar pede o credor e a forma num modal pequeno e refaz a lista; baixar é o link do arquivo.
sap.ui.define(["crm/controller/Lista", "sap/m/MessageToast", "crm/servico/formulario"], (Lista, MessageToast, formulario) => {
  "use strict"

  return Lista.extend("crm.controller.ArquivoDeAcordos", {
    endereco: "/arquivo-de-acordos",

    texto(chave) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave)
    },

    abrirAcordo(evento) {
      this.navegar("acordo", { id: String(evento.getSource().getBindingContext("dados").getProperty("acordo_id")) })
    },

    exportar() {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("arquivo.exportar.titulo"), descricao: this.texto("arquivo.exportar.ajuda"), escopo: "agreement_export",
        url: "/arquivo-de-acordos", botao: this.texto("arquivo.exportar"),
        campos: [{ nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: this.getView().getModel("dados").getProperty("/credores") },
          { nome: "form", rotulo: this.texto("acordos.forma"), tipo: "opcoes", opcoes: [{ id: "news", nome: this.texto("arquivo.novidades") }, { id: "full", nome: this.texto("arquivo.completo") }] }]
      }).then((resposta) => { MessageToast.show(resposta.mensagem || ""); this.carregar() })
    }
  })
})
