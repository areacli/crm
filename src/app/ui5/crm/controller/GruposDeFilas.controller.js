// Grupos das filas (15, R353, R358): criar e editar o grupo e a estratégia de um usuário no painel lateral, pelo construtor de formulário; excluir é
// botão direto do menu da linha. Valem na hora, sem conferência.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/base/strings/formatMessage", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/painel"],
  (Controller, JSONModel, formatMessage, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel) => {
  "use strict"

  return Controller.extend("crm.controller.GruposDeFilas", {
    formatarTexto: formatMessage,

    onInit() {
      this.credor = this.getView().getViewData()?.argumentos?.["?filtro"]?.tenant_id || ""
      this.getView().setModel(new JSONModel({ credores: [], grupos: [] }), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false }), "ui")
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    async carregar() {
      const dados = await http.obter(`/filas/grupos.json?tenant_id=${encodeURIComponent(this.credor)}`)
      this.credor = dados.credor_id
      this.getView().getModel("dados").setData(dados)
    },

    mudarCredor(evento) {
      this.credor = evento.getParameter("item").getKey()
      this.carregar()
    },

    concluir(resposta) {
      if (resposta.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    painel() {
      return painel(this.byId("colunas"), this.getView().getModel("ui"))
    },

    formularioDoGrupo(grupo, url, metodo, titulo) {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo, emPainel: this.painel(), escopo: "group", url, metodo, botao: this.texto("acao.salvar"),
        campos: [
          { nome: "name", rotulo: this.texto("enquadramento.nome"), tipo: "texto", obrigatorio: true, max: 100, valor: grupo.nome },
          { nome: "user_ids", rotulo: this.texto("filas.grupos.usuarios"), tipo: "varios", opcoes: grupo.usuarios, valor: grupo.selecionados,
            ajuda: grupo.usuarios.length ? null : this.texto("filas.grupos.semUsuarios") },
          { nome: "filas", rotulo: this.texto("filas.grupos.filasEOrdem"), tipo: "grupo" },
          ...grupo.filas.map((fila) => ({ nome: `queue_positions.${fila.id}`, rotulo: fila.nome, tipo: "numero", valor: fila.posicao ?? "" }))
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    async criar() {
      const grupo = await http.obter(`/filas/grupos/novo.json?tenant_id=${this.credor}`)
      this.formularioDoGrupo(grupo, `/filas/grupos?tenant_id=${this.credor}`, "POST", this.texto("filas.grupos.criar"))
    },

    async editar(grupo) {
      const dados = await http.obter(`/filas/grupos/${grupo.id}/editar.json`)
      this.formularioDoGrupo(dados, `/filas/grupos/${grupo.id}`, "PATCH", this.texto("filas.grupos.editar", [grupo.nome]))
    },

    async excluir(grupo) {
      try {
        this.concluir(await http.excluir(`/filas/grupos/${grupo.id}`))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    async estrategia(evento) {
      const usuario = evento.getSource().getBindingContext("dados").getObject()
      const dados = await http.obter(`/filas/estrategias/${usuario.id}/editar.json?tenant_id=${this.credor}`)
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("filas.estrategia.titulo", [dados.nome]), descricao: this.texto("filas.estrategia.ajuda"),
        emPainel: this.painel(), escopo: "strategy", url: `/filas/estrategias/${usuario.id}?tenant_id=${this.credor}`, metodo: "PATCH", botao: this.texto("acao.salvar"),
        campos: [
          { nome: "mode", rotulo: this.texto("filas.estrategia"), tipo: "opcoes", opcoes: dados.modos, valor: dados.modo },
          { nome: "filas", rotulo: this.texto("filas.estrategia.filasDe", [dados.credor]), tipo: "grupo" },
          ...dados.filas.flatMap((fila) => [
            { nome: `positions.${fila.id}`, rotulo: this.texto("filas.estrategia.posicao", [fila.nome]), tipo: "numero", valor: fila.posicao },
            { nome: `weights.${fila.id}`, rotulo: this.texto("filas.estrategia.peso", [fila.nome]), tipo: "numero", valor: fila.peso }
          ]),
          ...(dados.outras ? [{ nome: "outras", rotulo: dados.outras, tipo: "grupo" }] : [])
        ]
      }).then((resposta) => this.concluir(resposta))
    },

    acoes(evento) {
      const grupo = evento.getSource().getBindingContext("dados").getObject()
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: [
        new MenuItem({ text: this.texto("acao.editar"), press: () => this.editar(grupo) }),
        new MenuItem({ text: this.texto("acao.excluir"), press: () => this.excluir(grupo) })
      ] })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
