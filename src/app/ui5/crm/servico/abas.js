// Abas da aplicação (padrões de interface, P27): uma aba por tela e uma por ficha, vivas enquanto abertas, lembradas na janela
// (sessionStorage), no máximo 12. A aba com trabalho por salvar não se fecha sozinha e pede confirmação ao fechar.
sap.ui.define(["sap/m/TabContainerItem", "sap/ui/core/mvc/XMLView", "sap/m/MessageBox", "crm/servico/telas"], (TabContainerItem, XMLView, MessageBox, telas) => {
  "use strict"

  const LIMITE = 12
  const CHAVE = "crm.abas"

  return class Abas {
    constructor(componente, container, roteador) {
      this.componente = componente
      this.container = container
      this.roteador = roteador
      this.abertas = new Map() // chave → { rota, argumentos, item, view, ordem }
      this.ordem = 0
      container.attachItemSelect((evento) => this.aoSelecionar(evento))
      container.attachItemClose((evento) => this.aoFechar(evento))
    }

    static chave(rota, argumentos) {
      return `${rota}:${JSON.stringify(argumentos || {})}`
    }

    // Abre a aba da rota (ou seleciona a que já existe). `selecionar: false` só recria (as abas lembradas ao recarregar).
    async abrir(rota, argumentos = {}, { selecionar = true } = {}) {
      const tela = telas.porRota(rota)
      if (!tela) return
      const chave = Abas.chave(rota, tela.chaveDaAba ? tela.chaveDaAba(argumentos) : argumentos)
      let aba = this.abertas.get(chave)
      if (!aba) {
        aba = { rota, argumentos, ordem: ++this.ordem }
        this.abertas.set(chave, aba)
        aba.item = new TabContainerItem({ key: chave, name: tela.titulo })
        this.container.addItem(aba.item)
        aba.view = await this.componente.runAsOwner(() => XMLView.create({ viewName: tela.view, viewData: { argumentos, aba: aba.item } }))
        aba.item.addContent(aba.view)
        this.limitar()
      } else if (aba.view?.getController().mudarArgumentos) {
        aba.view.getController().mudarArgumentos(argumentos)
        aba.argumentos = argumentos
      }
      aba.ordem = ++this.ordem
      if (selecionar) this.container.setSelectedItem(aba.item)
      this.lembrar()
    }

    aoSelecionar(evento) {
      const aba = this.abertas.get(evento.getParameter("item")?.getKey())
      if (aba) this.roteador.navTo(aba.rota, aba.argumentos, true)
    }

    aoFechar(evento) {
      const item = evento.getParameter("item")
      const aba = this.abertas.get(item?.getKey())
      if (!aba?.view?.getController().temTrabalho?.()) return this.fechar(item.getKey())
      evento.preventDefault()
      const i18n = this.componente.getModel("i18n").getResourceBundle()
      MessageBox.confirm(i18n.getText("abas.descartar"), {
        actions: [i18n.getText("abas.descartar.acao"), MessageBox.Action.CANCEL],
        emphasizedAction: i18n.getText("abas.descartar.acao"),
        onClose: (acao) => acao === i18n.getText("abas.descartar.acao") && this.fechar(item.getKey(), true)
      })
    }

    fechar(chave, remover = false) {
      const aba = this.abertas.get(chave)
      if (!aba) return
      this.abertas.delete(chave)
      // Fechada pelo "×", a própria TabContainer retira a aba; fechada por aqui (confirmação, limite), retira-se antes. Destrói-se depois do evento.
      if (remover) this.container.removeItem(aba.item)
      setTimeout(() => aba.item.destroy())
      this.lembrar()
      if (this.abertas.size === 0) this.roteador.navTo("inicio", {}, true)
    }

    // A 13ª aba fecha a mais antiga sem trabalho por salvar.
    limitar() {
      if (this.abertas.size <= LIMITE) return
      const livre = [...this.abertas.entries()].sort((a, b) => a[1].ordem - b[1].ordem).find(([, aba]) => !aba.view?.getController().temTrabalho?.())
      if (livre) {
        this.fechar(livre[0], true)
      }
    }

    lembrar() {
      const lista = [...this.abertas.values()].sort((a, b) => this.container.indexOfItem(a.item) - this.container.indexOfItem(b.item))
      try { sessionStorage.setItem(CHAVE, JSON.stringify(lista.map(({ rota, argumentos }) => ({ rota, argumentos })))) } catch { /* sem memória da janela */ }
    }

    async restaurar() {
      let lista = []
      try { lista = JSON.parse(sessionStorage.getItem(CHAVE) || "[]") } catch { lista = [] }
      for (const { rota, argumentos } of lista) await this.abrir(rota, argumentos, { selecionar: false })
    }

    // Título da aba (a ficha põe o nome do cliente quando carrega).
    static titulo(item, texto) {
      item?.setName(texto)
    }
  }
})
