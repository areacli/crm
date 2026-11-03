// Enquadramento financeiro (13, R265 a R272, R276, R292 a R294; 09, R160, R165; 11, R207a, R246): o JSON da mesma rota, por credor. Incluir segmento e editar
// regras no painel lateral; mover e excluir no menu da linha; parâmetros e políticas de encargos pelo "Conferir mudança" do cartão, só com os campos que
// mudaram. Tudo isso devolve o endereço da conferência do impacto, que abre numa aba. Os parâmetros dos acordos gravam direto. Tempo real pelo recurso
// `credores`. Com `?filtro.editar` (o "Voltar e editar" da conferência), abre as regras daquele item.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/painel", "crm/servico/tempo-real", "crm/servico/gravar", "crm/servico/telas"],
  (Controller, JSONModel, Menu, MenuItem, MessageToast, MessageBox, http, formulario, painel, tempoReal, gravar, telas) => {
  "use strict"

  const PARAMETROS = ["charge_fine_pct", "charge_interest_pct", "charge_index", "charge_days_convention", "charge_fine_base"]
  const BASE = "/configuracao/enquadramento-financeiro"

  const vazio = () => ({ credor_id: "", credores: [], pode_mudar: false, recalculo: {}, itens: [], parametros: {}, parametros_texto: {}, politicas: {}, opcoes: {},
    acordo: {}, acordo_itens: [] })

  return Controller.extend("crm.controller.EnquadramentoFinanceiro", {
    onInit() {
      const filtro = this.getView().getViewData()?.argumentos?.["?filtro"] || {}
      this.credor = filtro.tenant_id ? String(filtro.tenant_id) : ""
      this.editarAoCarregar = filtro.editar
      this.originais = { parametros: {}, politicas: {} }
      this.getView().setModel(new JSONModel(vazio()), "dados")
      this.getView().setModel(new JSONModel({ painelAberto: false, detalhe: null }), "ui")
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => { if (mensagem.acao !== "atualizar" || (mensagem.registros || []).some((credor) => String(credor.id) === this.credor)) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // A aba já aberta recebe outro credor ou o pedido de editar um item (vindo da conferência).
    mudarArgumentos(argumentos) {
      const filtro = argumentos?.["?filtro"] || {}
      const credor = filtro.tenant_id ? String(filtro.tenant_id) : this.credor
      if (credor === this.credor && !filtro.editar) return
      this.credor = credor
      this.editarAoCarregar = filtro.editar
      this.carregar()
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    painel() {
      return painel(this.byId("colunas"), this.getView().getModel("ui"))
    },

    async obter(url) {
      try {
        return await http.obter(url)
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
        return null
      }
    },

    async carregar() {
      const dados = await this.obter(`${BASE}.json?tenant_id=${encodeURIComponent(this.credor)}`)
      if (!dados) return
      this.credor = dados.credor_id || ""
      // O que veio do servidor, para mandar à conferência só os campos que mudaram.
      this.originais = {
        parametros: { ...(dados.parametros || {}) },
        politicas: Object.fromEntries(Object.entries(dados.politicas || {}).map(([campo, politica]) => [campo, politica.valor]))
      }
      const ui = this.getView().getModel("ui")
      const detalhe = ui.getProperty("/detalhe")
      ui.setProperty("/detalhe", (detalhe && (dados.itens || []).find((item) => item.id === detalhe.id)) || null)
      this.getView().getModel("dados").setData({ ...vazio(), ...dados })
      if (this.editarAoCarregar) {
        const id = String(this.editarAoCarregar)
        this.editarAoCarregar = null
        // Tira o pedido do endereço da aba, para que voltar a ela não abra as regras de novo.
        this.getOwnerComponent().getRouter().navTo("enquadramentoFinanceiro", { "?filtro": { tenant_id: this.credor } }, true)
        this.editarRegras(id)
      }
    },

    mudarCredor(evento) {
      this.credor = evento.getParameter("item").getKey()
      this.getView().getModel("ui").setProperty("/detalhe", null)
      this.carregar()
    },

    mostrarDetalhe(evento) {
      this.getView().getModel("ui").setProperty("/detalhe", evento.getParameter("listItem").getBindingContext("dados").getObject())
    },

    // Mudanças no enquadramento devolvem o endereço da conferência (/configuracao/conferencias-do-enquadramento/<id>): ela abre numa aba.
    conferir(resposta) {
      const caminho = new URL(resposta.destino, window.location.origin).pathname
      const id = caminho.split("/").pop()
      this.getOwnerComponent().getRouter().navTo("conferenciaDoEnquadramento", { id })
    },

    async incluir() {
      const escolhas = await this.obter(`${BASE}/incluir.json?tenant_id=${encodeURIComponent(this.credor)}`)
      if (!escolhas) return
      if (!escolhas.segmentos.length) return MessageBox.information(this.texto("financeiro.semSegmento"))
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("financeiro.incluir"), descricao: this.texto("financeiro.incluir.ajuda"),
        emPainel: this.painel(), escopo: "tier", url: `${BASE}?tenant_id=${encodeURIComponent(this.credor)}`, botao: this.texto("enquadramento.conferir"),
        campos: [
          { nome: "segment_id", rotulo: this.texto("enquadramento.segmento"), tipo: "opcoes", opcoes: escolhas.segmentos, obrigatorio: true,
            ajuda: escolhas.segmentos_de_clientes ? this.texto("financeiro.incluir.semClientes") : undefined },
          { nome: "before_id", rotulo: this.texto("enquadramento.posicao"), tipo: "opcoes", opcoes: escolhas.posicoes, valor: "" },
          { nome: "copy_from_id", rotulo: this.texto("financeiro.copiarDe"), tipo: "opcoes", opcoes: escolhas.copiar_de, valor: escolhas.copiar_padrao,
            ajuda: this.texto("financeiro.copiarDe.ajuda") }
        ]
      }).then((resposta) => this.conferir(resposta))
    },

    async editarRegras(id) {
      const regras = await this.obter(`${BASE}/${encodeURIComponent(id)}/regras.json`)
      if (!regras) return
      const { valores, opcoes } = regras
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("financeiro.regras.titulo", [regras.nome]), descricao: regras.ajuda,
        emPainel: this.painel(), escopo: "tier", metodo: "PATCH", url: `${BASE}/${encodeURIComponent(id)}`, botao: this.texto("enquadramento.conferir"),
        campos: [
          { nome: "grupoEncargos", rotulo: this.texto("financeiro.regras.encargos"), tipo: "grupo" },
          { nome: "fine_pct", rotulo: this.texto("financeiro.multa"), tipo: "valor", valor: valores.fine_pct, ajuda: this.texto("financeiro.regras.multa.ajuda") },
          { nome: "interest_kind", rotulo: this.texto("financeiro.regras.juros"), tipo: "opcoes", opcoes: opcoes.juros, valor: valores.interest_kind,
            ajuda: this.texto("financeiro.regras.juros.ajuda") },
          { nome: "interest_pct", rotulo: this.texto("financeiro.regras.taxaFixa"), tipo: "valor", valor: valores.interest_pct },
          { nome: "interest_form", rotulo: this.texto("financeiro.regras.forma"), tipo: "opcoes", opcoes: opcoes.formas, valor: valores.interest_form },
          { nome: "index_code", rotulo: this.texto("financeiro.correcao"), tipo: "opcoes", opcoes: opcoes.indices, valor: valores.index_code },
          { nome: "fees_pct", rotulo: this.texto("financeiro.regras.honorarios"), tipo: "valor", valor: valores.fees_pct },
          { nome: "fees_in_contract", rotulo: this.texto("financeiro.regras.honorariosNoContrato"), tipo: "marca", valor: valores.fees_in_contract,
            ajuda: this.texto("financeiro.regras.honorarios.ajuda") },
          { nome: "days_convention", rotulo: this.texto("financeiro.convencao"), tipo: "opcoes", opcoes: opcoes.convencoes, valor: valores.days_convention },
          { nome: "fine_base", rotulo: this.texto("financeiro.baseDaMulta"), tipo: "opcoes", opcoes: opcoes.bases, valor: valores.fine_base },
          { nome: "grupoPromessa", rotulo: this.texto("financeiro.regras.promessa"), tipo: "grupo" },
          { nome: "promise_max_days", rotulo: this.texto("financeiro.regras.prazoDaPromessa"), tipo: "numero", valor: valores.promise_max_days, obrigatorio: true,
            ajuda: this.texto("financeiro.regras.prazoDaPromessa.ajuda") }
        ]
      }).then((resposta) => this.conferir(resposta))
    },

    async executar(pedido) {
      try {
        this.conferir(await pedido())
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    mover(item, direcao) {
      this.executar(() => http.enviar(`${BASE}/${encodeURIComponent(item.id)}/movimento`, { movement: { direction: direcao } }))
    },

    // A página do segmento: na SPA, se já foi portada; senão, a página do servidor.
    abrirSegmento(url) {
      const destino = telas.doCaminho(url)
      if (destino) this.getOwnerComponent().getRouter().navTo(destino.tela.rota, destino.argumentos)
      else window.location.assign(url)
    },

    acoes(evento) {
      const item = evento.getSource().getBindingContext("dados").getObject()
      const itens = [new MenuItem({ text: this.texto("financeiro.editarRegras"), press: () => this.editarRegras(item.id) })]
      if (!item.trilha_padrao) {
        if (!item.primeiro) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaCima"), press: () => this.mover(item, "up") }))
        if (!item.ultimo) itens.push(new MenuItem({ text: this.texto("enquadramento.moverParaBaixo"), press: () => this.mover(item, "down") }))
        itens.push(new MenuItem({ text: this.texto("financeiro.excluir"), press: () => this.executar(() => http.excluir(`${BASE}/${encodeURIComponent(item.id)}`)) }))
        if (item.segmento_url) itens.push(new MenuItem({ text: this.texto("financeiro.abrirSegmento"), press: () => this.abrirSegmento(item.segmento_url) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    },

    // Encargos do credor: só os campos do cartão que mudaram vão à conferência (09, R163).
    async enviarEncargos(mudancas) {
      if (!Object.keys(mudancas).length) return MessageToast.show(this.texto("financeiro.nadaMudou"))
      this.executar(() => http.alterar(`/configuracao/encargos?tenant_id=${encodeURIComponent(this.credor)}`, { charges: mudancas }))
    },

    conferirParametros() {
      const atuais = this.getView().getModel("dados").getProperty("/parametros") || {}
      const mudaram = PARAMETROS.filter((campo) => String(atuais[campo] ?? "") !== String(this.originais.parametros[campo] ?? ""))
      this.enviarEncargos(Object.fromEntries(mudaram.map((campo) => [campo, atuais[campo] ?? ""])))
    },

    conferirPoliticas() {
      const politicas = this.getView().getModel("dados").getProperty("/politicas") || {}
      const mudaram = Object.keys(politicas).filter((campo) => politicas[campo].valor !== this.originais.politicas[campo])
      this.enviarEncargos(Object.fromEntries(mudaram.map((campo) => [campo, politicas[campo].valor])))
    },

    // Parâmetros dos acordos (11, R207a, R246): os do credor e o valor próprio de cada item (vazio herda); gravam sem conferência.
    salvarAcordos() {
      const dados = this.getView().getModel("dados").getData()
      const tiers = Object.fromEntries((dados.acordo_itens || []).map(({ id, nome, ...valores }) => [id, valores]))
      gravar(this, "alterar", "/configuracao/parametros-de-acordo", { tenant_id: this.credor, credor: dados.acordo, tiers })
    }
  })
})
