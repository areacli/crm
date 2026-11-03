// Operações credenciadas (14, R306, R319): a lista da mesma rota; credenciar no painel lateral (a senha temporária do gestor aparece uma vez); as
// políticas de cada credor gravam pela rota de sempre.
sap.ui.define(["crm/controller/Lista", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario", "crm/servico/painel",
  "crm/servico/senha-temporaria"],
  (Lista, JSONModel, MessageToast, MessageBox, http, formulario, painel, senhaTemporaria) => {
  "use strict"

  return Lista.extend("crm.controller.Operacoes", {
    endereco: "/operacoes",
    filtroInicial: { per_page: 20, page: 1 },

    onInit() {
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      Lista.prototype.onInit.apply(this, arguments)
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    abrir(evento) {
      this.navegar("operacao", { id: String(this.objetoDaLinha(evento).id) })
    },

    credenciar() {
      const credores = this.getView().getModel("dados").getProperty("/credores")
      const campos = credores.length > 1
        ? [{ nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: credores }]
        : [{ nome: "tenant_id", tipo: "oculto", valor: credores[0]?.id }]
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("operacoes.credenciar"), descricao: this.texto("operacoes.credenciar.ajuda"),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "operation", url: "/operacoes", botao: this.texto("operacoes.credenciar.botao"),
        campos: [
          ...campos,
          { nome: "cnpj", rotulo: this.texto("operacoes.cnpj"), tipo: "texto", obrigatorio: true, max: 18 },
          { nome: "novo", rotulo: this.texto("operacoes.seNaoExiste"), tipo: "grupo" },
          { nome: "legal_name", rotulo: this.texto("operacoes.razaoSocial"), tipo: "texto", max: 200 },
          { nome: "short_name", rotulo: this.texto("operacoes.nomeCurto"), tipo: "texto", max: 60, ajuda: this.texto("operacoes.nomeCurto.ajuda") },
          { nome: "manager_name", rotulo: this.texto("operacoes.gestor"), tipo: "texto", max: 200 },
          { nome: "manager_email", rotulo: this.texto("operacoes.gestorEmail"), tipo: "texto", max: 200, ajuda: this.texto("operacoes.gestorEmail.ajuda") }
        ]
      }).then((resposta) => {
        MessageToast.show(resposta.mensagem || "", { duration: 6000 })
        senhaTemporaria(this, resposta)
        this.carregar()
      })
    },

    async salvarPoliticas(evento) {
      const politica = evento.getSource().getBindingContext("dados").getObject()
      try {
        const resposta = await http.alterar(`/operacoes/politicas?tenant_id=${politica.credor_id}`, { policies: {
          operation_exclusive: politica.exclusiva === "0", operation_default_exposure: politica.exposicao, operation_exposure_business_days: politica.dias_uteis,
          operation_sees_other_deals: politica.ve_outros_acordos === "1", operation_other_contact_attempts: politica.outros_acionamentos === "0" ? "summary" : "hidden",
          operation_manager_links: politica.gestor_da_vinculos === "1"
        } })
        MessageToast.show(resposta.mensagem, { duration: 6000 })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
      this.carregar()
    }
  })
})
