// Tratar divergência (05, R100): a nota e a escolha num modal pequeno, com as escolhas que o servidor oferece para aquela divergência.
sap.ui.define(["sap/m/MessageToast", "crm/servico/http", "crm/servico/formulario"], (MessageToast, http, formulario) => {
  "use strict"

  return async (controlador, id) => {
    const i18n = controlador.getOwnerComponent().getModel("i18n").getResourceBundle()
    const divergencia = await http.obter(`/divergencias-de-valor/${id}.json`)
    const resposta = await formulario.abrir({
      textoCancelar: i18n.getText("acao.cancelar"), titulo: i18n.getText("divergencias.tratar"), descricao: i18n.getText("divergencias.tratar.ajuda", [divergencia.titulo]),
      aviso: divergencia.aviso_do_valor, escopo: "handling", url: `/divergencias-de-valor/${id}/tratamento`, botao: i18n.getText("divergencias.tratar"),
      campos: [{ nome: "note", rotulo: i18n.getText("divergencias.nota"), tipo: "textoLongo", obrigatorio: true, max: 500, ajuda: i18n.getText("divergencias.nota.ajuda") },
        { nome: "choice", rotulo: i18n.getText("divergencias.oQueFazer"), tipo: "opcoes", opcoes: divergencia.escolhas }]
    })
    if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
    return resposta
  }
})
