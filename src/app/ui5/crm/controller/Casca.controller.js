// Casca da SPA (decisão 0025): menu do Rails (as mesmas permissões), abas da aplicação (P27) e roteador sobre o hash.
sap.ui.define([
  "sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/tnt/NavigationListItem", "sap/tnt/NavigationListGroup",
  "sap/m/Menu", "sap/m/MenuItem", "crm/servico/http", "crm/servico/abas", "crm/servico/telas", "crm/servico/sessao", "crm/servico/tempo-real"
], (Controller, JSONModel, NavigationListItem, NavigationListGroup, Menu, MenuItem, http, Abas, telas, sessao, tempoReal) => {
  "use strict"

  return Controller.extend("crm.controller.Casca", {
    onInit() {
      this.iniciar()
    },

    async iniciar() {
      this.getView().setModel(new JSONModel({ secoes: [], busca: false, avisos: 0 }), "menu")
      const roteador = this.getOwnerComponent().getRouter()
      roteador.addRoute({ name: "inicio", pattern: "" })
      roteador.addRoute({ name: "senha", pattern: "senha" })
      telas.todas().forEach((tela) => roteador.addRoute({ name: tela.rota, pattern: tela.padrao }))
      this.abas = new Abas(this.getOwnerComponent(), this.byId("abas"), roteador)
      this.byId("abas").attachEvent("itemClose", () => setTimeout(() => this.mostrarVazio()))
      roteador.attachRouteMatched((evento) => this.aoCasarRota(evento))
      // O menu (com os contadores e o sino) se refaz a cada (re)conexão e quando chega um aviso novo.
      tempoReal.ouvir("*conectado", () => this.carregarMenu())
      tempoReal.ouvir("avisos", () => this.carregarMenu())
      await Promise.all([this.carregarMenu(), this.abas.restaurar()])
      roteador.initialize()
      tempoReal.iniciar()
    },

    async carregarMenu() {
      const menu = await http.obter("/menu")
      this.getView().getModel("menu").setData(menu)
      // O menu só se redesenha quando muda (um item ou um contador): a cada conexão ele chega igual, e redesenhar trocaria o foco e piscaria.
      const assinatura = JSON.stringify(menu.secoes)
      if (assinatura === this.assinaturaDoMenu) return
      this.assinaturaDoMenu = assinatura
      const lista = this.byId("itensDoMenu")
      lista.destroyItems()
      const item = ({ rotulo, caminho, contador, subitens }) => new NavigationListItem({
        text: contador ? `${rotulo} (${contador})` : rotulo, key: caminho || rotulo, expanded: false,
        items: (subitens || []).map((sub) => new NavigationListItem({ text: sub.rotulo, key: sub.caminho }))
      })
      menu.secoes.forEach((secao) => {
        if (!secao.titulo) return secao.itens.forEach((dados) => lista.addItem(item(dados)))
        lista.addItem(new NavigationListGroup({ text: secao.titulo, items: secao.itens.map(item) }))
      })
    },

    aoCasarRota(evento) {
      const nome = evento.getParameter("name")
      if (nome === "senha") {
        this.getOwnerComponent().getRouter().navTo("inicio", {}, true)
        return this.trocarSenha()
      }
      if (nome === "inicio") {
        // Sem tela no hash: a aba que já estava aberta; sem nenhuma, o Resumo (a entrada do sistema, R23) para quem o vê; senão, o aviso.
        const primeira = this.byId("abas").getItems()[0]
        if (primeira) return this.byId("abas").setSelectedItem(primeira)
        const veResumo = this.getView().getModel("menu").getProperty("/secoes").some((secao) => secao.itens.some((item) => item.caminho === "/resumo"))
        if (veResumo) return this.getOwnerComponent().getRouter().navTo("resumo", {}, true)
        return this.mostrarVazio()
      }
      // Na ficha, o menu começa recolhido (design system, revisão 9); a pessoa o mostra de novo pelo botão do cabeçalho.
      if (nome === "cliente" && !this.menuRecolhidoNaFicha) {
        this.menuRecolhidoNaFicha = true
        this.esconderMenu(true)
      }
      this.abas.abrir(nome, evento.getParameter("arguments")).then(() => this.mostrarVazio())
    },

    mostrarVazio() {
      const vazio = this.byId("abas").getItems().length === 0
      this.byId("vazio").setVisible(vazio)
      this.byId("abas").setVisible(!vazio)
    },

    // Item do menu: a tela da SPA abre numa aba; a que ainda é página do servidor abre como página (porte por fases).
    escolherNoMenu(evento) {
      const caminho = evento.getParameter("item").getKey()
      if (!caminho?.startsWith("/")) return
      const destino = telas.doCaminho(caminho)
      if (destino) return this.getOwnerComponent().getRouter().navTo(destino.tela.rota, destino.argumentos)
      window.location.assign(caminho)
    },

    // Esconder e mostrar o menu (design system, revisão 7): escondido, o menu some e o conteúdo ocupa a largura toda (não vira faixa de ícones).
    alternarMenu() {
      this.esconderMenu(!this.byId("pagina").hasStyleClass("menu-escondido"))
    },

    esconderMenu(esconder) {
      this.byId("pagina").toggleStyleClass("menu-escondido", esconder)
    },

    irAoInicio() {
      this.getOwnerComponent().getRouter().navTo("inicio")
    },

    buscar(evento) {
      const termo = evento.getParameter("query")?.trim()
      if (termo) this.getOwnerComponent().getRouter().navTo("clientes", { "?filtro": { q: termo } })
    },

    abrirAvisos() {
      window.location.assign("/avisos")
    },

    // Trocar a senha (R39): três campos num diálogo (regra de ação); os erros de cada campo vêm do servidor.
    async trocarSenha() {
      this.dialogoDaSenha ??= await this.loadFragment({ name: "crm.fragment.TrocarSenha" })
      ;["atual", "nova", "repetir"].forEach((id) => this.byId(id).setValue("").setValueState("None"))
      this.byId("mensagemDaSenha").setVisible(false)
      this.dialogoDaSenha.open()
    },

    async salvarSenha() {
      const CAMPOS = { current_password: "atual", password: "nova", password_confirmation: "repetir" }
      Object.values(CAMPOS).forEach((id) => this.byId(id).setValueState("None"))
      try {
        const resposta = await http.alterar("/senha", { password: { current_password: this.byId("atual").getValue(), password: this.byId("nova").getValue(), password_confirmation: this.byId("repetir").getValue() } })
        this.dialogoDaSenha.close()
        sap.ui.require(["sap/m/MessageToast"], (MessageToast) => MessageToast.show(resposta.mensagem))
      } catch (erro) {
        Object.entries(erro.corpo?.erros || {}).forEach(([campo, mensagens]) => this.byId(CAMPOS[campo])?.setValueState("Error").setValueStateText(mensagens.join(" ")))
        this.byId("mensagemDaSenha").setText(erro.corpo?.mensagem || erro.message).setVisible(true)
      }
    },

    fecharSenha() {
      this.dialogoDaSenha.close()
    },

    abrirMenuDoUsuario(evento) {
      const i18n = this.getOwnerComponent().getModel("i18n").getResourceBundle()
      this.menuDoUsuario ??= new Menu({
        items: [
          new MenuItem({ text: i18n.getText("casca.trocarSenha"), icon: "sap-icon://key", press: () => this.trocarSenha(), visible: this.getOwnerComponent().getModel("sessao").getProperty("/pode_trocar_senha") }),
          new MenuItem({ text: i18n.getText("casca.sair"), icon: "sap-icon://log", press: () => sessao.sair(this.getOwnerComponent()) })
        ]
      })
      this.getView().addDependent(this.menuDoUsuario)
      this.menuDoUsuario.openBy(evento.getSource())
    }
  })
})
