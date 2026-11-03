// Casca da SPA (decisão 0025): menu do Rails (as mesmas permissões) na barra superior (padrões de interface, revisão 34), abas da aplicação (P27)
// e roteador sobre o hash.
sap.ui.define([
  "sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/ui/Device", "sap/m/Button", "sap/m/MenuButton", "sap/m/OverflowToolbarLayoutData",
  "sap/m/Menu", "sap/m/MenuItem", "sap/m/ResponsivePopover", "sap/m/SearchField", "crm/servico/http", "crm/servico/abas", "crm/servico/telas", "crm/servico/sessao", "crm/servico/tempo-real"
], (Controller, JSONModel, Device, Button, MenuButton, OverflowToolbarLayoutData, Menu, MenuItem, ResponsivePopover, SearchField, http, Abas, telas, sessao, tempoReal) => {
  "use strict"

  // Abaixo desta largura a busca vira um botão com a lupa (design system, 17.5): a busca larga (18 rem) tiraria grupos do menu para o "⋯" em 1366 px.
  const BUSCA_LARGA = 1600
  // Abaixo desta largura (tablet) o botão do usuário fica só com o ícone e o nome na dica, para os grupos do menu caberem na barra.
  const USUARIO_COM_NOME = 1100
  const larguras = () => ({ buscaCurta: window.innerWidth < BUSCA_LARGA, usuarioCurto: window.innerWidth < USUARIO_COM_NOME })

  const rotuloComContador = (rotulo, contador) => (contador ? `${rotulo} (${contador})` : rotulo)

  return Controller.extend("crm.controller.Casca", {
    onInit() {
      this.iniciar()
    },

    async iniciar() {
      this.getView().setModel(new JSONModel({ secoes: [], busca: false, avisos: 0, ...larguras() }), "menu")
      Device.resize.attachHandler(() => Object.entries(larguras()).forEach(([chave, valor]) => this.getView().getModel("menu").setProperty(`/${chave}`, valor)))
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
      Object.assign(menu, larguras())
      this.getView().getModel("menu").setData(menu)
      // O menu só se redesenha quando muda (um item ou um contador): a cada conexão ele chega igual, e redesenhar trocaria o foco e piscaria.
      const assinatura = JSON.stringify(menu.secoes)
      if (assinatura === this.assinaturaDoMenu) return
      this.assinaturaDoMenu = assinatura
      this.montarMenu(menu.secoes)
    },

    // Um botão por item de primeiro nível (Resumo, Clientes, Acionamentos) e por grupo de um item só; um botão com lista por grupo, com as áreas
    // de subitens (Filas, Operações, Configuração) como submenus. O contador do grupo é a soma dos itens. Os botões entram antes do espaçador; o
    // que não cabe vai ao "⋯", os grupos antes do primeiro nível (padrões de interface, revisão 34, P1).
    montarMenu(secoes) {
      const cabecalho = this.byId("cabecalho")
      ;(this.botoesDoMenu || []).forEach((botao) => botao.destroy())
      this.botoesDoMenu = []
      let posicao = cabecalho.indexOfContent(this.byId("fimDoMenu"))
      const inserir = (botao, prioridade) => {
        botao.setLayoutData(new OverflowToolbarLayoutData({ priority: prioridade }))
        botao.addStyleClass("item-do-menu")
        cabecalho.insertContent(botao, posicao++)
        this.botoesDoMenu.push(botao)
      }
      const direto = (item, prioridade) => {
        const botao = new Button({ text: rotuloComContador(item.rotulo, item.contador), type: "Transparent", press: () => this.abrirCaminho(item.caminho) })
        botao.data("caminhos", [item.caminho])
        inserir(botao, prioridade)
      }
      const itemDaLista = (item) => new MenuItem({
        text: rotuloComContador(item.rotulo, item.contador), key: item.caminho || "",
        items: (item.subitens || []).map((sub) => new MenuItem({ text: sub.rotulo, key: sub.caminho }))
      })
      secoes.forEach((secao) => {
        if (!secao.titulo) return secao.itens.forEach((item) => direto(item, "High"))
        const unico = secao.itens.length === 1 && !secao.itens[0].subitens?.length
        if (unico) return direto(secao.itens[0], "Low")
        const total = secao.itens.reduce((soma, item) => soma + (Number(item.contador) || 0), 0)
        const lista = new Menu({ items: secao.itens.map(itemDaLista), itemSelected: (evento) => this.abrirCaminho(evento.getParameter("item").getKey()) })
        const botao = new MenuButton({ text: rotuloComContador(secao.titulo, total), type: "Transparent", menu: lista })
        botao.data("caminhos", secao.itens.flatMap((item) => [item.caminho, ...(item.subitens || []).map((sub) => sub.caminho)]).filter(Boolean))
        inserir(botao, "Low")
      })
      this.marcarAtual()
    },

    // O grupo da tela atual leva o sublinhado amarelo: o botão que tem o caminho mais longo que é começo do endereço da aba ativa.
    marcarAtual() {
      const atual = (window.location.hash.replace(/^#/, "") || "/").split("?")[0]
      let melhor = null
      let tamanho = 0
      ;(this.botoesDoMenu || []).forEach((botao) => {
        botao.removeStyleClass("atual")
        botao.data("caminhos").forEach((caminho) => {
          const base = caminho.split("?")[0]
          if ((atual === base || atual.startsWith(`${base}/`)) && base.length > tamanho) {
            melhor = botao
            tamanho = base.length
          }
        })
      })
      melhor?.addStyleClass("atual")
    },

    abrirBusca(evento) {
      const campo = new SearchField({ width: "100%", placeholder: this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("casca.busca"), search: (busca) => {
        this.buscar(busca)
        this.buscaCurta.close()
      } })
      this.buscaCurta?.destroy()
      this.buscaCurta = new ResponsivePopover({ showHeader: false, placement: "Bottom", contentWidth: "22rem", content: [campo], initialFocus: campo })
      this.buscaCurta.addStyleClass("sapUiContentPadding")
      this.getView().addDependent(this.buscaCurta)
      this.buscaCurta.openBy(evento.getSource())
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
      setTimeout(() => this.marcarAtual())
      this.abas.abrir(nome, evento.getParameter("arguments")).then(() => this.mostrarVazio())
    },

    mostrarVazio() {
      const vazio = this.byId("abas").getItems().length === 0
      this.byId("vazio").setVisible(vazio)
      this.byId("abas").setVisible(!vazio)
    },

    // Item do menu: a tela da SPA abre numa aba; a que ainda é página do servidor abre como página (porte por fases).
    abrirCaminho(caminho) {
      if (!caminho?.startsWith("/")) return
      const destino = telas.doCaminho(caminho)
      if (destino) return this.getOwnerComponent().getRouter().navTo(destino.tela.rota, destino.argumentos)
      window.location.assign(caminho)
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
