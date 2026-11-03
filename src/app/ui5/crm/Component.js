// Componente do CRM (decisão 0025). Modelos globais: `sessao` (quem está conectado e a demonstração) e `i18n` (textos de tela, do manifest).
sap.ui.define(["sap/ui/core/UIComponent", "sap/ui/model/json/JSONModel", "sap/ui/Device"], (UIComponent, JSONModel, Device) => {
  "use strict"

  return UIComponent.extend("crm.Component", {
    metadata: { manifest: "json", interfaces: ["sap.ui.core.IAsyncContentCreation"] },

    init() {
      UIComponent.prototype.init.apply(this, arguments)
      const configuracao = this.getComponentData().configuracao
      this.setModel(new JSONModel({ ...configuracao, demonstracaoAtiva: Boolean(configuracao.demonstracao) }), "sessao")
    },

    // Densidade do design system (revisão 13): compacta com ponteiro fino, confortável com toque.
    densidade() {
      return Device.support.touch && !Device.system.desktop ? "sapUiSizeCozy" : "sapUiSizeCompact"
    }
  })
})
