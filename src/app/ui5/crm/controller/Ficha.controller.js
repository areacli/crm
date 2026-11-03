// Ficha do cliente (R22): o JSON da mesma rota do Rails; o contrato escolhido no cartão Contratos recorta a ficha inteira (padrões de
// interface, revisões 21 e 28); o título da aba é o nome do cliente (P27). As partes ainda não portadas levam à página do servidor.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/base/strings/formatMessage",
  "crm/servico/http", "crm/servico/formulario", "crm/servico/tempo-real"],
  (Controller, JSONModel, Menu, MenuItem, MessageToast, formatMessage, http, formulario, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Ficha", {
    formatarTexto: formatMessage,

    onInit() {
      const { argumentos, aba } = this.getView().getViewData()
      this.id = argumentos.id
      this.aba = aba
      this.contrato = null
      this.getView().setModel(new JSONModel({ indicadores: [], avisos: [], contratos: [], titulos: [], pode: {}, abas: {}, dados: {}, em_cobranca: {} }), "dados")
      this.getView().setModel(new JSONModel({ eventos: [], tipos: [], pagina: 1, paginas: 1 }), "linha")
      this.getView().setModel(new JSONModel({ painelAberto: false, detalhes: {} }), "ui")
      this.getView().setModel(new JSONModel({ linhas: [], pagina: 1, paginas: 1, total: 0 }), "acionamentos")
      this.paginaDeAcionamentos = 1
      this.filtroDaLinha = { tipo: "", pagina: 1 }
      this.carregar()
      this.mudarArgumentos(argumentos)
      // Tempo real (decisão 0025): o cliente desta ficha mudou (acionamento, promessa, acordo), ou a conexão voltou: a ficha se refaz, mesmo em aba escondida.
      // O painel aberto não perde o que foi escrito: só a ficha e a linha do tempo se refazem.
      this.desligar = [
        tempoReal.ouvir("clientes", (mensagem) => {
          const ids = [...(mensagem.registros || []).map((cliente) => cliente.id), ...(mensagem.removidos || [])]
          if (mensagem.acao === "recarregar" || ids.includes(Number(this.id))) this.carregar()
        }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // A ficha já aberta recebe um pedido pelo endereço (o "Registrar acionamento" da lista de clientes, por exemplo).
    mudarArgumentos(argumentos) {
      if (argumentos["?acao"]?.painel === "acionamento") this.registrarAcionamento()
    },

    async carregar() {
      const view = this.getView()
      view.setBusy(true)
      try {
        const consulta = this.contrato ? `?contrato=${this.contrato}` : ""
        const dados = await http.obter(`/clientes/${this.id}.json${consulta}`)
        view.getModel("dados").setData(dados)
        view.getModel("ui").setProperty("/detalhes", {})
        this.aba?.setName(dados.nome)
        this.carregarLinhaDoTempo()
        if (this.byId("abasDaFicha").getSelectedKey() === "acionamentos") this.carregarAcionamentos()
      } catch (erro) {
        sap.ui.require(["sap/m/MessageBox"], (MessageBox) => MessageBox.error(erro.corpo?.mensagem || this.texto(erro.status === 404 ? "erro.naoEncontrado" : "erro.geral")))
      } finally {
        view.setBusy(false)
      }
    },

    // Linha do tempo (padrões de interface, revisão 24): filtro por tipo e páginas de 10, no contrato escolhido.
    async carregarLinhaDoTempo() {
      const parametros = new URLSearchParams({ linha_pagina: this.filtroDaLinha.pagina })
      if (this.filtroDaLinha.tipo) parametros.set("linha", this.filtroDaLinha.tipo)
      if (this.contrato) parametros.set("contrato", this.contrato)
      this.getView().getModel("linha").setData(await http.obter(`/clientes/${this.id}/linha-do-tempo.json?${parametros}`))
    },

    filtrarLinhaDoTempo(evento) {
      const tipo = evento.getParameter("item").getKey()
      this.filtroDaLinha = { tipo: tipo === "todos" ? "" : tipo, pagina: 1 }
      this.carregarLinhaDoTempo()
    },

    paginaDaLinha(passo) {
      this.filtroDaLinha.pagina += passo
      this.carregarLinhaDoTempo()
    },

    texto(chave, ...valores) {
      return formatMessage(this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave), valores)
    },

    escolherContrato(evento) {
      this.contrato = evento.getParameter("listItem").getBindingContext("dados").getProperty("id")
      this.carregar()
    },

    verTodosOsContratos() {
      this.contrato = null
      this.carregar()
    },

    // Registrar acionamento (04): o painel lateral na segunda coluna da ficha, nesta aba (P27: trocar de aba não perde o rascunho).
    async registrarAcionamento() {
      if (!this.paginaDoAcionamento) {
        this.getView().setModel(new JSONModel({}), "registro")
        this.paginaDoAcionamento = await this.loadFragment({ name: "crm.fragment.RegistrarAcionamento", addToDependents: false })
        this.byId("colunas").addMidColumnPage(this.paginaDoAcionamento)
      }
      this.byId("colunas").toMidColumnPage(this.paginaDoAcionamento)
      await this.carregarRegistro(`/clientes/${this.id}/acionamentos/registrar.json`)
      this.byId("colunas").setLayout("TwoColumnsBeginExpanded")
      this.getView().getModel("ui").setProperty("/painelAberto", true)
      this.byId("canal").focus()
    },

    // O estado do formulário vem do servidor; o que a pessoa já digitou (contato, texto, datas) é mantido.
    async carregarRegistro(endereco) {
      const modelo = this.getView().getModel("registro")
      const dados = await http.obter(endereco)
      dados.contratosComVazio = [{ id: "", nome: this.texto("acionamento.semContrato") }, ...dados.contratos]
      modelo.setData(dados)
    },

    valoresDoRegistro() {
      return this.getView().getModel("registro").getProperty("/valores") || {}
    },

    // Mudou uma escolha que muda o formulário: pede o estado novo com tudo o que foi preenchido.
    atualizarRegistro() {
      const parametros = new URLSearchParams()
      Object.entries(this.valoresDoRegistro()).forEach(([campo, valor]) => {
        if (Array.isArray(valor)) valor.forEach((item) => parametros.append(`contact_attempt[${campo}][]`, item))
        else if (valor) parametros.set(`contact_attempt[${campo}]`, valor)
      })
      return this.carregarRegistro(`/clientes/${this.id}/acionamentos/campos.json?${parametros}`)
    },

    marcarTituloDaPromessa() {
      const titulos = this.getView().getModel("registro").getProperty("/promessa/titulos") || []
      this.getView().getModel("registro").setProperty("/valores/promise_bill_ids", titulos.filter((titulo) => titulo.marcado).map((titulo) => titulo.id))
      this.atualizarRegistro()
    },

    marcarSalvarContato(evento) {
      this.getView().getModel("registro").setProperty("/valores/save_contact", evento.getParameter("selected") ? "1" : "0")
    },

    async salvarAcionamento() {
      const botao = this.byId("salvarAcionamento")
      botao.setBusy(true)
      try {
        const resposta = await http.enviar(`/clientes/${this.id}/acionamentos`, { contact_attempt: this.valoresDoRegistro() })
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.fecharPainel()
        this.carregar()
      } catch (erro) {
        this.getView().getModel("registro").setProperty("/erro", erro.corpo?.mensagem || erro.message)
      } finally {
        botao.setBusy(false)
      }
    },

    fecharPainel() {
      this.byId("colunas").setLayout("OneColumn")
      this.getView().getModel("ui").setProperty("/painelAberto", false)
      this.getView().getModel("registro")?.setData({})
    },

    // Aba com o painel aberto e algo escolhido ou escrito: não fecha sozinha (P27).
    temTrabalho() {
      if (this.byId("colunas").getLayout() === "OneColumn") return false
      return Object.values(this.valoresDoRegistro()).some((valor) => (Array.isArray(valor) ? valor.length > 0 : Boolean(valor)))
    },

    // Simular acordo (fluxo rico): aba própria (regra de ação, padrões de interface revisão 33).
    simularAcordo() {
      this.getOwnerComponent().getRouter().navTo("simulacao", { id: String(this.id) })
    },

    // --- Abas da ficha

    escolherAba(evento) {
      if (evento.getParameter("key") === "acionamentos") this.carregarAcionamentos()
    },

    async carregarAcionamentos() {
      const parametros = new URLSearchParams({ page: this.paginaDeAcionamentos })
      if (this.contrato) parametros.set("contrato", this.contrato)
      this.getView().getModel("acionamentos").setData(await http.obter(`/clientes/${this.id}/acionamentos.json?${parametros}`))
    },

    paginaDosAcionamentos(passo) {
      this.paginaDeAcionamentos += passo
      this.carregarAcionamentos()
    },

    // Detalhe da linha escolhida (P26), abaixo da tabela: a tabela diz, no dado `detalhe`, qual detalhe ela mostra.
    mostrarDetalhe(evento) {
      const tabela = evento.getSource()
      const item = evento.getParameter("listItem")
      tabela.getItems().forEach((linha) => linha.setHighlight(linha === item ? "Information" : "None"))
      const modelo = tabela.getBindingInfo("items").model
      this.getView().getModel("ui").setProperty(`/detalhes/${tabela.data("detalhe")}`, item.getBindingContext(modelo).getObject())
    },

    // --- Ações: cada uma usa a rota de sempre do Rails; a resposta é o aviso, e a ficha se refaz.

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      this.carregar()
    },

    async executar(url, metodo = "POST") {
      try {
        this.concluir(await http[metodo === "POST" ? "enviar" : "alterar"](url, {}))
      } catch (erro) {
        sap.ui.require(["sap/m/MessageBox"], (MessageBox) => MessageBox.error(erro.corpo?.mensagem || erro.message))
      }
    },

    // Painel lateral para formulário médio (regra de ação): a página vai à segunda coluna, e a lateral de dados dá lugar a ela.
    painel() {
      const colunas = this.byId("colunas")
      const ui = this.getView().getModel("ui")
      return {
        mostrar: (pagina) => { colunas.addMidColumnPage(pagina); colunas.toMidColumnPage(pagina); colunas.setLayout("TwoColumnsBeginExpanded"); ui.setProperty("/painelAberto", true) },
        fechar: (pagina) => { colunas.removeMidColumnPage(pagina); colunas.setLayout("OneColumn"); ui.setProperty("/painelAberto", false) }
      }
    },

    abrirFormulario(definicao) {
      return formulario.abrir({ textoCancelar: this.texto("acao.cancelar"), ...definicao }).then((resposta) => this.concluir(resposta))
    },

    menu(evento, itens) {
      const menu = new Menu({ items: itens.filter(Boolean).map(([chave, acao]) => new MenuItem({ text: this.texto(chave), press: acao })), closed: () => setTimeout(() => menu.destroy()) })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    },

    linha(evento) {
      return evento.getSource().getBindingContext("dados").getObject()
    },

    motivo(chave = "ficha.motivo") {
      return { nome: "reason", rotulo: this.texto(chave), tipo: "texto", obrigatorio: true, max: 300 }
    },

    maisAcoes(evento) {
      const pode = this.getView().getModel("dados").getProperty("/pode")
      const nome = this.getView().getModel("dados").getProperty("/nome")
      this.menu(evento, [
        pode.editar_cadastro && ["ficha.editarNome", () => this.abrirFormulario({
          titulo: this.texto("ficha.editarNome"), descricao: this.texto("ficha.editarNome.ajuda"), emPainel: this.painel(), escopo: "customer", metodo: "PATCH",
          url: `/clientes/${this.id}/nome`, botao: this.texto("ficha.salvarNome"), campos: [{ nome: "name", rotulo: this.texto("ficha.nome"), tipo: "texto", valor: nome, obrigatorio: true }]
        })],
        pode.editar_cadastro && ["ficha.criarContato", () => this.criarContato()],
        pode.transferir_credito && ["ficha.transferirCredito", () => this.transferirCredito()],
        pode.direitos_do_titular && ["ficha.exportarDados", () => this.exportarDados()],
        pode.anonimizar && ["ficha.anonimizar", () => this.abrirFormulario({
          titulo: this.texto("ficha.anonimizar.titulo"), descricao: this.texto("ficha.anonimizar.ajuda"), perigoso: true, escopo: "anonymization",
          url: `/clientes/${this.id}/anonimizacao`, botao: this.texto("ficha.anonimizar.titulo"),
          campos: [{ ...this.motivo(), ajuda: this.texto("ficha.motivo.ajuda") }, { nome: "document", rotulo: this.texto("ficha.anonimizar.documento"), tipo: "texto", obrigatorio: true, max: 18, ajuda: this.texto("ficha.anonimizar.documento.ajuda") }]
        })]
      ])
    },

    // Exportar (07, R129): a página para imprimir abre numa janela nova.
    exportarDados() {
      formulario.abrir({
        textoCancelar: this.texto("acao.cancelar"), titulo: this.texto("ficha.exportarDados"), descricao: this.texto("ficha.exportarDados.ajuda"), escopo: "export",
        url: `/clientes/${this.id}/exportacao`, botao: this.texto("ficha.exportarDados"), campos: [{ ...this.motivo(), ajuda: this.texto("ficha.motivo.ajuda") }]
      }).then((resposta) => { if (resposta.destino) window.open(resposta.destino, "_blank", "noopener") })
    },

    acoesDoTitulo(evento) {
      const titulo = this.linha(evento)
      this.menu(evento, [["ficha.usarCredito.acao", () => this.abrirFormulario({
        titulo: this.texto("ficha.usarCredito.titulo"), descricao: this.texto("ficha.usarCredito", titulo.usar_credito), escopo: "credit_use", url: `/clientes/${this.id}/uso-de-credito`,
        botao: this.texto("ficha.usarCredito.titulo"), campos: [{ nome: "bill_id", tipo: "oculto", valor: titulo.id }, { nome: "amount", rotulo: this.texto("ficha.valorAUsar"), tipo: "valor", obrigatorio: true }]
      })]])
    },

    aprovarPromessa(evento) {
      this.executar(`/promessas/${this.linha(evento).id}/aprovacao`)
    },

    acoesDaPromessa(evento) {
      const promessa = this.linha(evento)
      const comMotivo = (chave, caminho) => this.abrirFormulario({
        titulo: this.texto(chave), descricao: promessa.numero, perigoso: true, escopo: "promise", url: `/promessas/${promessa.id}/${caminho}`, botao: this.texto(chave), campos: [this.motivo()]
      })
      this.menu(evento, [
        promessa.pode.recusar && ["promessa.recusar", () => comMotivo("promessa.recusar", "recusa")],
        promessa.pode.cancelar && ["promessa.cancelar", () => comMotivo("promessa.cancelar", "cancelamento")]
      ])
    },

    camposDeEndereco() {
      const ufs = this.getView().getModel("dados").getProperty("/ufs").map((uf) => ({ id: uf, nome: uf }))
      return [["street", "contato.logradouro", 200], ["number", "contato.numero", 20], ["complement", "contato.complemento", 100], ["district", "contato.bairro", 100], ["city", "contato.cidade", 100]]
        .map(([nome, chave, max]) => ({ nome, rotulo: this.texto(chave), tipo: "texto", max }))
        .concat([{ nome: "state", rotulo: this.texto("contato.uf"), tipo: "opcoes", vazio: true, opcoes: [{ id: "", nome: "" }, ...ufs] }, { nome: "zip", rotulo: this.texto("contato.cep"), tipo: "texto", max: 9 }])
    },

    criarContato() {
      this.abrirFormulario({
        titulo: this.texto("ficha.criarContato"), descricao: this.texto("contato.criar.ajuda"), emPainel: this.painel(), escopo: "contact", url: `/clientes/${this.id}/contatos`,
        botao: this.texto("ficha.criarContato"),
        campos: [{ nome: "kind", rotulo: this.texto("ficha.contatos.tipo"), tipo: "opcoes", opcoes: ["phone", "email", "address"].map((id) => ({ id, nome: this.texto(`contato.tipo.${id}`) })) },
          { nome: "value", rotulo: this.texto("contato.valor"), tipo: "texto", max: 254 }, ...this.camposDeEndereco()]
      })
    },

    acoesDoContato(evento) {
      const contato = this.linha(evento)
      const caminho = `/clientes/${this.id}/contatos/${contato.id}`
      const situacao = (chave, status, campo) => this.abrirFormulario({
        titulo: this.texto(chave), descricao: `${contato.tipo}: ${contato.valor}`, perigoso: status === "invalid", escopo: "status", metodo: "PATCH", url: `${caminho}/situacao`,
        botao: this.texto(chave), campos: [{ nome: "status", tipo: "oculto", valor: status }, campo]
      })
      this.menu(evento, [
        contato.pode.editar && ["contato.editar", () => this.abrirFormulario(contato.endereco
          ? { titulo: this.texto("contato.editar"), descricao: contato.valor, emPainel: this.painel(), escopo: "contact", metodo: "PATCH", url: caminho, botao: this.texto("acao.salvar"), campos: this.camposDeEndereco() }
          : { titulo: this.texto("contato.editar"), descricao: this.texto("contato.editar.ajuda"), escopo: "contact", metodo: "PATCH", url: caminho, botao: this.texto("acao.salvar"),
              campos: [{ nome: "value", rotulo: contato.tipo, tipo: "texto", valor: contato.valor, obrigatorio: true, max: 254 }] })],
        contato.pode.invalidar && ["contato.invalidar", () => situacao("contato.invalidar", "invalid", this.motivo())],
        contato.pode.nao_perturbe && ["contato.naoPerturbe", () => situacao("contato.naoPerturbe", "do_not_disturb", { nome: "requested_on", rotulo: this.texto("contato.dataDoPedido"), tipo: "data", obrigatorio: true, valor: new Date().toISOString().slice(0, 10) })],
        contato.pode.validar && ["contato.validar", () => situacao("contato.validar", "valid", this.motivo())]
      ])
    },

    transferirCredito() {
      this.abrirFormulario({
        titulo: this.texto("ficha.transferirCredito"), descricao: this.texto("credito.transferir.ajuda"), emPainel: this.painel(), escopo: "credit_transfer", url: `/clientes/${this.id}/transferencias-de-credito`,
        botao: this.texto("credito.transferir"),
        campos: [{ nome: "from_contract_id", rotulo: this.texto("credito.origem"), tipo: "opcoes", opcoes: this.getView().getModel("dados").getProperty("/origens_de_transferencia") || [] },
          { nome: "to_code", rotulo: this.texto("credito.destino"), tipo: "texto", obrigatorio: true, max: 100 },
          { nome: "amount", rotulo: this.texto("ficha.valor"), tipo: "valor", obrigatorio: true, ajuda: this.texto("credito.valor.ajuda") }, this.motivo()]
      })
    },

    alocarCredito(evento) {
      const contrato = evento.getSource().getBindingContext("dados").getObject()
      this.abrirFormulario({
        titulo: this.texto("ficha.alocarCredito"), descricao: contrato.titulo, escopo: "credit_allocation", url: `/clientes/${this.id}/alocacao-de-credito`, botao: this.texto("credito.alocar"),
        campos: [{ nome: "contract_id", tipo: "oculto", valor: contrato.id }, { nome: "bill_id", rotulo: this.texto("credito.tituloDoContrato"), tipo: "opcoes", opcoes: contrato.titulos_alocaveis },
          { nome: "amount", rotulo: this.texto("ficha.valor"), tipo: "valor", obrigatorio: true }]
      })
    }
  })
})
