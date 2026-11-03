// Resultados de acionamento (R66, R67): o JSON da mesma rota; criar e editar (cinco campos) no painel lateral; mover para cima ou para baixo é botão
// do menu da linha; desativar e reativar pedem confirmação curta. Todas as ações vão às rotas de sempre.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast",
  "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario", "crm/servico/painel"],
  (Controller, JSONModel, formatMessage, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel) => {
  "use strict"

  const ENDERECO = "/configuracao/resultados-de-acionamento"

  return Controller.extend("crm.controller.ResultadosDeAcionamento", {
    formatarTexto: formatMessage,

    onInit() {
      this.getView().setModel(new JSONModel({ credores: [], grupos: [], tipos: [], retornos: [] }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const view = this.getView()
      view.setBusy(true)
      try {
        view.getModel("dados").setData(await http.obter(`${ENDERECO}.json`))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      } finally {
        view.setBusy(false)
      }
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    // Os campos comuns a criar e editar; o tipo só se escolhe na criação (R67).
    campos(resultado, criando) {
      const dados = this.getView().getModel("dados")
      const campos = [
        { nome: "name", rotulo: this.texto("resultados.nome"), tipo: "texto", obrigatorio: true, max: 100, valor: resultado.nome, ajuda: this.texto("resultados.nome.ajuda") }
      ]
      if (criando) {
        campos.push({ nome: "kind", rotulo: this.texto("resultados.tipo"), tipo: "opcoes", opcoes: dados.getProperty("/tipos"), valor: resultado.tipo_id, ajuda: this.texto("resultados.tipo.ajuda") })
      }
      campos.push(
        { nome: "return_rule", rotulo: this.texto("resultados.dataDeRetorno"), tipo: "opcoes", opcoes: dados.getProperty("/retornos"), valor: resultado.retorno_id, ajuda: this.texto("resultados.dataDeRetorno.ajuda") },
        { nome: "invalidates_contact", rotulo: this.texto("resultados.invalida"), tipo: "marca", valor: resultado.invalida, ajuda: this.texto("resultados.invalida.ajuda") },
        { nome: "allows_promise", rotulo: this.texto("resultados.admitePromessa"), tipo: "marca", valor: resultado.admite_promessa, ajuda: this.texto("resultados.admitePromessa.ajuda") }
      )
      return campos
    },

    criar() {
      const credores = this.getView().getModel("dados").getProperty("/credores")
      const credor = credores.length > 1
        ? { nome: "tenant_id", rotulo: this.texto("clientes.credor"), tipo: "opcoes", opcoes: credores, valor: credores[0]?.id }
        : { nome: "tenant_id", tipo: "oculto", valor: credores[0]?.id }
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("resultados.novo"),
        descricao: credores.length > 1 ? null : this.texto("resultados.credor", [credores[0]?.nome]),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "contact_result", url: ENDERECO, botao: this.texto("acao.salvar"),
        campos: [credor, ...this.campos({ tipo_id: "spoke_with_customer", retorno_id: "allowed", invalida: false, admite_promessa: false }, true)]
      }).then((resposta) => this.concluir(resposta))
    },

    editar(resultado) {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("resultados.editar", [resultado.nome]),
        descricao: this.texto("resultados.editar.ajuda", [resultado.credor, resultado.tipo]),
        emPainel: painel(this.byId("colunas"), this.getView().getModel("ui")), escopo: "contact_result", url: `${ENDERECO}/${resultado.id}`, metodo: "PATCH",
        botao: this.texto("acao.salvar"), campos: this.campos(resultado, false)
      }).then((resposta) => this.concluir(resposta))
    },

    editarDaLinha(evento) {
      this.editar(evento.getSource().getBindingContext("dados").getObject())
    },

    async mover(resultado, direcao) {
      try {
        this.concluir(await http.enviar(`${ENDERECO}/${resultado.id}/movimento`, { movement: { direction: direcao } }))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    // Desativar (some da escolha, os acionamentos antigos continuam) ou reativar, com confirmação curta.
    ativacao(resultado) {
      const desativar = resultado.ativo
      const acao = this.texto(desativar ? "resultados.desativar" : "resultados.reativar")
      MessageBox[desativar ? "warning" : "confirm"](this.texto(desativar ? "resultados.desativar.mensagem" : "resultados.reativar.mensagem"), {
        title: this.texto(desativar ? "resultados.desativar.pergunta" : "resultados.reativar.pergunta", [resultado.nome]),
        actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
        onClose: async (escolha) => {
          if (escolha !== acao) return
          const url = `${ENDERECO}/${resultado.id}/ativacao`
          try { this.concluir(await (desativar ? http.excluir(url) : http.enviar(url, {}))) } catch (erro) { MessageBox.error(erro.corpo?.mensagem || erro.message) }
        }
      })
    },

    acoes(evento) {
      const resultado = evento.getSource().getBindingContext("dados").getObject()
      const itens = [new MenuItem({ text: this.texto("acao.editar"), press: () => this.editar(resultado) })]
      if (!resultado.primeiro) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaCima"), press: () => this.mover(resultado, "up") }))
      if (!resultado.ultimo) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaBaixo"), press: () => this.mover(resultado, "down") }))
      itens.push(new MenuItem({ text: this.texto(resultado.ativo ? "resultados.desativar" : "resultados.reativar"), press: () => this.ativacao(resultado) }))
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
